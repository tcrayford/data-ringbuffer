module Main where

import           Control.Monad          (when)
import           Control.Applicative    ((*>))
import           Control.Concurrent     ( newEmptyMVar
                                        , putMVar
                                        , takeMVar
                                        , forkIO
                                        )
import           Control.DeepSeq        (rnf)
import           Data.RingBuffer
import           Data.RingBuffer.Vector
import           Util
import           Data.IORef
import qualified Data.Vector as V


main :: IO ()
main = do
    res   <- newIORef 0
    con   <- newConsumer (\x -> atomicModifyIORef' res (\n -> (n + 1, ())))
    seqr  <- newSequencer [con]
    buf   <- newRingBuffer bufferSize 0
    done  <- newEmptyMVar
    start <- now

    forkIO $ mapM_ (pub buf seqr) [0..iterations]
    forkIO $ consumeAll buf modmask (newBarrier seqr V.empty) con done

    takeMVar done *> now >>= printTiming iterations start
    x <- readIORef res
    when (x /= iterations) $ error $ "x was not expected total, got: " ++ show x ++ ", expected: " ++ show iterations

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

atomicModifyIORef' :: IORef a -> (a -> (a,b)) -> IO b
atomicModifyIORef' ref f = do
    b <- atomicModifyIORef ref
            (\x -> let (a, b) = f x
                    in (a, a `seq` b))
    b `seq` return b

-- vim: set ts=4 sw=4 et:
