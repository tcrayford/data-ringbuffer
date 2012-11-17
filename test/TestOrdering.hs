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

{-
main :: IO ()
main = hspec $ do
  describe "unicast disruptor" $
    prop "it delivers in order" prop_unicast_delivers_in_order
-}

main = go 10

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
