module Data.RingBuffer.Types
    ( -- * Types
      Barrier(..)
    , Consumer(..)
    , Sequence(..)
    , Sequencer(..)
    )
where

import           Data.IORef
import qualified Data.Vector as V


newtype Sequence = Sequence (IORef Int)


data Sequencer = Sequencer !Sequence
                           -- ^ cursor
                           !(V.Vector Sequence)
                           -- ^ gating (aka consumer) sequences

data Barrier = Barrier !Sequence
                       -- ^ cursor (must point to the same sequence as the
                       -- corresponding 'Sequencer')
                       !(V.Vector Sequence)
                       -- ^ dependent sequences (optional)

data Consumer a = Consumer (a -> IO ())
                           -- ^ consuming function
                           !Sequence
                           -- ^ consumer sequence


-- vim: set ts=4 sw=4 et:
