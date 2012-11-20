module Data.RingBuffer.Arbitrary where
import           Test.QuickCheck

newtype IterationCount = IterationCount Int deriving (Show, Eq)

instance Arbitrary IterationCount where
    arbitrary = fmap IterationCount $ choose (1, 70)
    shrink (IterationCount i) = fmap IterationCount (shrink i)

newtype ThreadSleep = ThreadSleep Int deriving (Show, Eq)

instance Arbitrary ThreadSleep where
    arbitrary = fmap ThreadSleep $ choose (0, 10)
    shrink (ThreadSleep n) = fmap ThreadSleep $ shrink n

newtype BufferSize = BufferSize Int deriving (Show, Eq)

instance Arbitrary BufferSize where
    arbitrary = do
        n <- (choose (1,20)) :: Gen Int
        return $! BufferSize (2 ^ (n + 1))

