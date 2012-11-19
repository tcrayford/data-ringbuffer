module Main where

import           Control.Concurrent     ( newEmptyMVar
                                        , putMVar
                                        , takeMVar
                                        , forkIO
                                        )
import           Control.DeepSeq        (rnf)
import           Control.Monad          (replicateM)
import           Data.RingBuffer
import           Data.RingBuffer.Vector
import           Util
import qualified Data.Vector as V


main :: IO ()
main = do
    con  <- newConsumer (return . rnf)
    seqr  <- newSequencer [con]
    availableToWriteTo  <- mkSeq
    buf   <- newRingBuffer bufferSize (0 :: Int)
    done <- newEmptyMVar
    start <- now

    forkIO $ mapM_ (pub buf seqr availableToWriteTo) (takeWhile (<= iterations) (iterate (+2) 0))
    forkIO $ mapM_ (pub buf seqr availableToWriteTo) (takeWhile (<= iterations) (iterate (+2) 1))
    forkChild buf seqr con done

    takeMVar done

    now >>= printTiming iterations start

    where
        bufferSize = 1024*8
        modmask    = bufferSize - 1

        pub buf seqr availableToWriteTo i = concPublishTo buf modmask seqr availableToWriteTo i

        forkChild buf seqr con lock = forkIO $
            consumeAll buf modmask (newBarrier seqr V.empty) con lock

        consumeAll buf modm barr con lock = do
            consumeFrom buf modm barr con
            consumed <- consumerSeq con
            if consumed >= iterations
                then putMVar lock ()
                else consumeAll buf modm barr con lock
