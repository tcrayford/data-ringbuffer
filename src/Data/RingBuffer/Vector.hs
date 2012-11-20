{-# LANGUAGE ScopedTypeVariables #-}
module Data.RingBuffer.Vector
    ( MVector(..)
    , newRingBuffer
    , consumeFrom
    , publishTo
    , batchPublishTo
    , concPublishTo
    , concBatchPublishTo
    , mapMV_
    )
where

import           Control.Monad        (unless)
import           Data.Bits
import qualified Data.Vector          as V
import qualified Data.Vector.Mutable  as MV

import           Data.RingBuffer
import qualified Data.RingBuffer.Class      as C
import           Data.RingBuffer.Internal
import           Data.RingBuffer.Types
import           Debug.Trace
import           Unsafe.Coerce


newtype MVector a = MVector (MV.IOVector a)

instance C.RingBuffer MVector where
    newRingBuffer      = newRingBuffer
    consumeFrom        = consumeFrom
    publishTo          = publishTo
    batchPublishTo     = batchPublishTo
    concPublishTo      = concPublishTo
    concBatchPublishTo = concBatchPublishTo


newRingBuffer :: Int -> a -> IO (MVector a)
newRingBuffer size zero = do
    mvec <- MV.replicate (ceilNextPowerOfTwo size) zero
    return (MVector mvec)

    where
        ceilNextPowerOfTwo i = shiftL 1 (32 - numberOfLeadingZeros (i - 1))

        numberOfLeadingZeros i = nlz i 1
            where
                nlz 0 _ = 32
                nlz i' n | shiftR i' 16 == 0 = nlz (shiftL i' 16) (n + 16)
                         | shiftR i' 24 == 0 = nlz (shiftL i'  8) (n +  8)
                         | shiftR i' 28 == 0 = nlz (shiftL i'  4) (n +  4)
                         | shiftR i' 30 == 0 = nlz (shiftL i'  2) (n +  2)
                         | otherwise = n - shiftR i' 31
{-# INLINE newRingBuffer #-}

consumeFrom :: MVector a -> Int -> Barrier -> Consumer a -> IO ()
consumeFrom (MVector mvec) modm barr (Consumer fn sq) = do
    consumeFrom' mvec

    where
        consumeFrom' mvec = do
            next  <- addAndGet sq 1
            avail <- waitFor barr next

            let start = next .&. modm
                len   = avail - next
                t = MV.take (len + 1) $ MV.drop start mvec

            cTrace "CONSUMEFROM ==============" $ return ()
            cTrace ("avail: " ++ show avail) $ return ()
            cTrace ("next: " ++ show next) $ return ()
            cTrace ("start: " ++ show start) $ return ()
            cTrace ("len: " ++ show len) $ return ()
            cTrace ("t.len: " ++ show (MV.length t)) $ return ()
            (s :: [Int]) <- fmap (unsafeCoerce . V.toList) (V.freeze t)
            cTrace ("t:" ++ show s) $ return ()

            mapMV_ fn t
            unless (MV.length t > len) $ do
                let remaining = (MV.take (1 + (len - MV.length t)) mvec)
                cTrace ("taking from the start with length: " ++ show ((len - MV.length t + 1))) $ return ()

                (s1 :: [Int]) <- fmap (unsafeCoerce . V.toList) (V.freeze remaining)
                cTrace ("remaining: " ++ show s1) $ return ()
                mapMV_ fn remaining

            writeSeq sq avail
{-# INLINE consumeFrom #-}


mapMV_ fn mvec = do
    go 0
    return ()
    where go n = if n == max then do return () else runFn n
          max = MV.length mvec
          runFn n = do
                     MV.unsafeRead mvec n >>= fn
                     go $! n + 1
{-# INLINE mapMV_ #-}

publishTo :: MVector a -> Int -> Sequencer -> Int -> a -> IO ()
publishTo (MVector mvec) modm seqr i v = do
    next <- claim seqr i (MV.length mvec)
    MV.unsafeWrite mvec (next .&. modm) v
    publish seqr next 1
{-# INLINE publishTo #-}

pTrace s = return ()
cTrace s a = a
    --trace ("                                                 " ++ s) a

batchPublishTo :: MVector a -> Int -> Sequencer -> Int -> [a] -> IO ()
batchPublishTo (MVector mvec) modm seqr i vs = do
    next <- claim seqr i (MV.length mvec)
    mapM_ update $ zip [next - len + 1..next] vs
    publish seqr next len

    where
        len = length vs

        update (n,x) = MV.unsafeWrite mvec (n .&. modm) x
{-# INLINE batchPublishTo #-}

concPublishTo :: MVector a -> Int -> Sequencer -> Sequence -> a -> IO ()
concPublishTo (MVector mvec) modm seqr sq v = do
    next <- nextSeq seqr sq (MV.length mvec)
    MV.unsafeWrite mvec (next .&. modm) v
    publish seqr next 1
{-# INLINE concPublishTo #-}

concBatchPublishTo :: MVector a -> Int -> Sequencer -> Sequence -> Int -> [a] -> IO ()
concBatchPublishTo (MVector mvec) modm seqr sq i vs = do
    next <- nextBatch seqr sq i (MV.length mvec)
    mapM_ update $ zip [next - len + 1..next] vs
    publish seqr next len

    where
        len = length vs

        update (n,x) = MV.unsafeWrite mvec (n .&. modm) x
{-# INLINE concBatchPublishTo #-}


-- vim: set ts=4 sw=4 et:
