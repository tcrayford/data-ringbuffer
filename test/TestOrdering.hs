import           Test.Hspec
import           Test.Hspec.QuickCheck(prop)
import           Test.QuickCheck
import           Test.QuickCheck.Monadic
import           Control.Concurrent(forkIO, threadDelay)
import           Control.Concurrent.MVar.Strict
import           Data.RingBuffer
import           Data.RingBuffer.Vector
import           Control.DeepSeq        (rnf)
import           Control.Monad
import           Data.RingBuffer.Arbitrary
import qualified Data.Vector as V

main :: IO ()
main = hspec $ describe "mapMV" $ do
    prop "loops over a mutable vector" $ prop_loops_over_mutable_vector
    prop "it delivers in order" prop_unicast_delivers_in_order
    prop "producer sequence never overtakes consumer" prop_producer_never_overtakes_consumer

prop_loops_over_mutable_vector :: [Int] -> Property
prop_loops_over_mutable_vector xs = monadicIO $ do
    x <- run $ newMVar []
    mvector <- run $ V.thaw (V.fromList xs)
    run $ mapMV_ (\n -> modifyMVar_ x (return . (++ [n]))) mvector
    res <- run $ takeMVar x
    if xs /= res
        then error $ "expected " ++ show xs ++ " to equal " ++ show res
        else return ()
    assert $ xs == res

prop_producer_never_overtakes_consumer :: IterationCount -> ThreadSleep -> ThreadSleep -> BufferSize -> Property
prop_producer_never_overtakes_consumer (IterationCount iterations) (ThreadSleep pdelay) (ThreadSleep cdelay) (BufferSize bufferSize) = monadicIO $ run $ do
    con <- newConsumer (\x -> do threadDelay cdelay; return (rnf x))
    seqr <- newSequencer [con]
    buf <- newRingBuffer bufferSize 0
    done <- newEmptyMVar

    let xs = [0..iterations]

    forkIO $ mapM_ (pub buf seqr) xs
    forkIO $ consumeAll buf modmask (newBarrier seqr V.empty) con done

    while (isEmptyMVar done) $ checkConsumerSequence seqr con bufferSize

    takeMVar done

    where
        modmask    = bufferSize - 1

        pub buf seqr i = do
                                 threadDelay pdelay
                                 publishTo buf modmask seqr i i

        consumeAll buf modm barr con lock = do
            consumeFrom buf modm barr con
            consumed <- consumerSeq con
            if consumed >= iterations
                then putMVar lock ()
                else consumeAll buf modm barr con lock

checkConsumerSequence :: Sequencer -> Consumer a -> Int -> IO ()
checkConsumerSequence seqr con bufferSize = do
    c <- getCursorValue seqr
    i <- consumerSeq con
    if (c - bufferSize) >= i
        then error $ "cursor went higher than the consumer sequence, cursor: " ++ show c ++ " consumer: " ++ show i
        else return ()

while :: IO Bool -> IO () -> IO ()
while test action = do
    x <- test
    when x $ do
                action
                while test action

prop_unicast_delivers_in_order :: IterationCount -> ThreadSleep -> ThreadSleep -> BufferSize -> Property
prop_unicast_delivers_in_order (IterationCount iterations) (ThreadSleep pubDelay) (ThreadSleep conDelay) (BufferSize bufferSize) = monadicIO $ run $ do
    let xs = [0..iterations]
    done  <- newEmptyMVar
    res   <- newMVar []
    con   <- newConsumer (myConsumer res)
    seqr  <- newSequencer [con]
    buf   <- newRingBuffer bufferSize 0

    forkIO $ mapM_ (pub buf seqr) xs
    forkIO $ consumeAll buf modmask (newBarrier seqr V.empty) con done res

    takeMVar done
    final <- takeMVar res
    unless (final == xs) $ do
        let diff = filter (\(x,y) -> x /= y) (zip final xs)
        error $ "final was: " ++ show final ++ " xs was: " ++ show xs ++ " diff: " ++ show diff


    where
        modmask    = bufferSize - 1

        pub buf seqr i = do
                                threadDelay pubDelay
                                publishTo buf modmask seqr i i

        myConsumer res x = do
                                threadDelay conDelay
                                modifyMVar_ res (return . (++ [x]))

        consumeAll buf modm barr con lock res = do
            consumeFrom buf modm barr con
            consumed <- consumerSeq con
            if consumed == iterations
                then do
                        putMVar lock ()
                else consumeAll buf modm barr con lock res

-- vim: set ts=4 sw=4 et:

