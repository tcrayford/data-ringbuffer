module Data.RingBuffer.Internal
    ( addAndGet
    , await
    , mkSeq
    , readSeq
    , writeSeq
    , minSeq
    )
where

import           Control.Applicative  ((<$>))
import           Data.CAS
import           Data.IORef
import           Data.RingBuffer.Types
import qualified Data.Vector as V


minSeq :: (V.Vector Sequence) -> IO Int
minSeq ss = V.foldM' go maxBound ss
    where go maxBound s = do
                n <- readSeq s
                if n < maxBound
                    then return $! n
                    else return $! maxBound
--fromIntegral . V.minimum <$> V.mapM readSeq ss
{-# INLINE minSeq #-}

await :: (V.Vector Sequence) -> Int -> Int -> IO Int
await gates n bufsize = do
    m <- minSeq gates
    if (n - bufsize < m) then return n else await gates n bufsize
{-# INLINE await #-}


addAndGet :: Sequence -> Int -> IO Int
addAndGet (Sequence ref) delta = do
    atomicModifyIORefCAS ref $! pair . (+delta)

    where
        pair x = (x, x)
{-# INLINE addAndGet #-}

mkSeq :: IO Sequence
mkSeq = do
    ref <- newIORef (-1)
    return $! Sequence ref

readSeq :: Sequence -> IO Int
readSeq (Sequence ref) = readIORef ref
{-# INLINE readSeq #-}

writeSeq :: Sequence -> Int -> IO ()
writeSeq (Sequence ref) = writeIORef ref
{-# INLINE writeSeq #-}


-- vim: set ts=4 sw=4 et:
