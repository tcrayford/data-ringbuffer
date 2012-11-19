import           Test.Hspec.Monadic
import           Test.Hspec.QuickCheck(prop)
import           Test.QuickCheck
import           Test.QuickCheck.Monadic
import           Control.Concurrent
import           Control.Concurrent.MVar
import           Data.RingBuffer
import           Data.RingBuffer.Vector
import qualified Data.Vector as V
import           Control.DeepSeq        (rnf)
import           Control.Monad
import           Debug.Trace
import qualified Data.Vector.Mutable  as MV
import qualified Data.Vector as V

{-
main :: IO ()
main = hspec $ do
  describe "unicast disruptor" $
-}

main = hspec $ describe "mapMV" $ do
    prop "loops over a mutable vector" $ prop_loops_over_mutable_vector
    --prop "it delivers in order" prop_unicast_delivers_in_order
    prop "producer sequence never overtakes consumer" $ prop_producer_never_overtakes_consumer

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

newtype IterationCount = IterationCount Int deriving (Show, Eq)

instance Arbitrary IterationCount where
    arbitrary = fmap IterationCount $ choose (1000, 100000)

prop_producer_never_overtakes_consumer :: IterationCount -> Property
prop_producer_never_overtakes_consumer (IterationCount iterations) = monadicIO $ run $ do
    con <- newConsumer (return .rnf)
    seqr <- newSequencer [con]
    buf <- newRingBuffer bufferSize 0
    done <- newEmptyMVar

    let xs = [0..iterations]

    forkIO $ mapM_ (pub buf seqr) xs
    forkIO $ consumeAll buf modmask (newBarrier seqr V.empty) con done

    while (isEmptyMVar done) $ checkConsumerSequence seqr con

    takeMVar done

    where
        bufferSize = 1024*8
        modmask    = bufferSize - 1

        pub buf seqr i = publishTo buf modmask seqr i i

        consumeAll buf modm barr con lock = do
            consumeFrom buf modm barr con
            consumed <- consumerSeq con
            if consumed >= iterations
                then putMVar lock ()
                else consumeAll buf modm barr con lock

checkConsumerSequence :: Sequencer -> Consumer a -> IO ()
checkConsumerSequence seqr con = do
    c <- getCursorValue seqr
    i <- consumerSeq con
    if c >= i
        then error "cursor went higher than the consumer sequence"
        else return ()

while :: IO Bool -> IO () -> IO ()
while test action = do
    x <- test
    if x
        then return ()
        else do
                action
                while test action

prop_unicast_delivers_in_order :: (Positive Int) -> Property
prop_unicast_delivers_in_order (Positive iterations) = monadicIO $ run $ go iterations

go iterations = do
    let xs = [0..iterations]
    done  <- newEmptyMVar
    res   <- newMVar []
    con   <- newConsumer (myConsumer res done)
    seqr  <- newSequencer [con]
    buf   <- newRingBuffer bufferSize 0

    forkIO $ mapM_ (pub buf seqr) xs
    forkIO $ consumeAll buf modmask (newBarrier seqr V.empty) con done res

    takeMVar done

    final <- takeMVar res
    unless (final == xs) $
      error $ "final was: " ++ show final ++ " xs was: " ++ show xs


    where
        bufferSize = 1024*8
        modmask    = bufferSize - 1

        pub buf seqr i = trace ("producing: " ++ show i) $ publishTo buf modmask seqr i i

        myConsumer res lock x = do
                            modifyMVar_ res (appendForTrace x)
                            if x == iterations
                              then putMVar lock ()
                              else return ()

        consumeAll buf modm barr con lock res = do
            consumeFrom buf modm barr con
            consumed <- consumerSeq con
            trace ("consumerseq was:" ++ show consumed) $ return ()
            if consumed >= iterations
                then putMVar lock ()
                else consumeAll buf modm barr con lock res

appendForTrace :: Int -> [Int] -> IO [Int]
appendForTrace x xs = do
  trace ("consumed was: " ++ show x) $ return ()
  return $! xs ++ [x]

-- vim: set ts=4 sw=4 et:
