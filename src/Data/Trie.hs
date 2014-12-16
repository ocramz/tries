{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE RankNTypes #-}

{- |

By defining an instance of 'TrieKey' with a 'GenericTrie' implementation
for 'Trie' all methods of 'TrieKey' can be derived automatically.

> data DemoType = DemoC1 Int | DemoC2 Int Int
>   deriving Generic
>
> instance TrieKey DemoType where
>   newtype Trie DemoType a = DemoTrie (GenericTrie DemoType a)
>
-}

module Data.Trie
  (
  -- * Trie operations
    TrieKey(..)
  -- * Generic instance generation
  , GenericTrie
  ) where



import Control.Applicative
import Control.Lens
import Data.Char (ord,chr)
import Data.Coerce
import Data.Foldable (Foldable(..))
import Data.Int
import Data.IntMap (IntMap)
import Data.Map (Map)
import Data.Maybe (isNothing)
import Data.Monoid (Monoid(..))
import Data.Semigroup (Option(..), Semigroup(..))
import Data.Traversable (fmapDefault, foldMapDefault)
import Data.Type.Coercion
import Data.Word
import GHC.Generics
import qualified Data.IntMap as IntMap
import qualified Data.Map as Map
import qualified Data.Foldable as Foldable


-- | Keys that support prefix-trie map operations.
--
-- All operations can be automatically derived when
-- the associated 'Trie' type is a /newtype/ of 'GenericTrie'.
class TrieKey k where
  -- | Associated datatype of tries indexable by keys of type @k@.
  --
  -- @
  -- Instances
  -- 'TrieKey' k => 'Functor'                ('Trie' k)
  -- 'TrieKey' k => 'Foldable'               ('Trie' k)
  -- 'TrieKey' k => 'Traversable'            ('Trie' k)
  -- 'TrieKey' k => 'TraversableWithIndex' k ('Trie' k)
  -- 'TrieKey' k => 'FunctorWithIndex'     k ('Trie' k)
  -- 'TrieKey' k => 'FoldableWithIndex'    k ('Trie' k)
  --
  -- ('Semigroup' a, 'TrieKey' k) => 'Monoid'    ('Trie' k a)
  -- ('Semigroup' a, 'TrieKey' k) => 'Semigroup' ('Trie' k a)
  --
  -- ('Eq' a, 'TrieKey' k) => 'Eq' ('Trie' k a)
  --
  -- 'Index'   ('Trie' k a) = k
  -- 'IxValue' ('Trie' k a) = a
  -- 'TrieKey' k => 'At'   ('Trie' k a)
  -- 'TrieKey' k => 'Ixed' ('Trie' k a)
  -- @
  data Trie k a

  -- | Returns 'True' when the 'Trie' contains no values.
  trieNull  :: Trie k a -> Bool
  default trieNull ::
    ( GTrieKey (Rep k)
    , Coercible (Trie k a) (GTrie (Rep k) a)
    ) =>
    Trie k a -> Bool
  trieNull = genericTrieNull

  -- | Returns a 'Trie' containing no values.
  trieEmpty :: Trie k a
  default trieEmpty ::
    ( GTrieKey (Rep k)
    , Generic k
    , Coercible (Trie k a) (GTrie (Rep k) a)
    ) => Trie k a
  trieEmpty = genericTrieEmpty

  -- | 'Lens' for visiting elements of the 'Trie'
  trieAt  :: k -> Lens' (Trie k a) (Maybe a)
  default trieAt ::
    ( GTrieKey (Rep k)
    , Generic k
    , Coercible (Trie k a) (GTrie (Rep k) a)
    ) =>
    k -> Lens' (Trie k a) (Maybe a)
  trieAt = genericTrieAt

  -- | Implementation of 'IndexedTraversal' used to implement
  -- 'TraversableWithIndex' and other classes listed above for all 'Trie's.
  trieITraverse :: IndexedTraversal k (Trie k a) (Trie k b) a b
  default trieITraverse ::
     ( Generic k
     , GTrieKey (Rep k)
     , Coercible (Trie k a) (GTrie (Rep k) a)
     , Coercible (Trie k b) (GTrie (Rep k) b)
     ) =>
     IndexedTraversal k (Trie k a) (Trie k b) a b
  trieITraverse = genericTrieITraverse

  -- | Implementation of the append operation used in
  -- the 'Semigroup' and 'Monoid' instances for 'Trie'.
  trieAppend :: Semigroup a => Trie k a -> Trie k a -> Trie k a
  default trieAppend ::
     ( GTrieKey (Rep k)
     , Coercible (Trie k a) (GTrie (Rep k) a)
     , Semigroup a
     ) =>
     Trie k a -> Trie k a -> Trie k a
  trieAppend = genericTrieAppend

instance TrieKey k => Functor     (Trie k) where fmap     = fmapDefault
instance TrieKey k => Foldable    (Trie k) where foldMap  = foldMapDefault
instance TrieKey k => Traversable (Trie k) where traverse = trieITraverse

instance (Semigroup a, TrieKey k) => Monoid (Trie k a) where
  mappend = trieAppend
  mempty  = trieEmpty

instance (Semigroup a, TrieKey k) => Semigroup (Trie k a) where
  (<>) = trieAppend

type instance Index   (Trie k a) = k
type instance IxValue (Trie k a) = a
instance TrieKey k => At   (Trie k a) where at = trieAt
instance TrieKey k => Ixed (Trie k a) where ix = ixAt


-- | Abstract type when generating tries from the 'Generic' representation of a key.
newtype GenericTrie k a = GenericTrie (GTrie (Rep k) a)



-- Base instances

instance TrieKey Int where
  newtype Trie Int a          = IntTrie (IntMap a)
  trieAt k                    = iso (\(IntTrie t) -> t) IntTrie . at k
  trieNull (IntTrie x)        = IntMap.null x
  trieEmpty                   = IntTrie IntMap.empty
  trieITraverse f (IntTrie x) = fmap IntTrie (itraversed f x)
  trieAppend (IntTrie x) (IntTrie y) = IntTrie (IntMap.unionWith (<>) x y)

instance TrieKey Int8 where
  newtype Trie Int8 a          = Int8Trie (IntMap a)
  trieAt k                     = iso (\(Int8Trie t) -> t) Int8Trie . at (fromEnum k)
  trieNull (Int8Trie x)        = IntMap.null x
  trieEmpty                    = Int8Trie IntMap.empty
  trieITraverse f (Int8Trie x) = fmap Int8Trie (reindexed (toEnum :: Int -> Int8) itraversed f x)
  trieAppend (Int8Trie x) (Int8Trie y) = Int8Trie (IntMap.unionWith (<>) x y)

instance TrieKey Int16 where
  newtype Trie Int16 a          = Int16Trie (IntMap a)
  trieAt k                      = iso (\(Int16Trie t) -> t) Int16Trie . at (fromEnum k)
  trieNull (Int16Trie x)        = IntMap.null x
  trieEmpty                     = Int16Trie IntMap.empty
  trieITraverse f (Int16Trie x) = fmap Int16Trie (reindexed (toEnum :: Int -> Int16) itraversed f x)
  trieAppend (Int16Trie x) (Int16Trie y) = Int16Trie (IntMap.unionWith (<>) x y)

instance TrieKey Int32 where
  newtype Trie Int32 a          = Int32Trie (IntMap a)
  trieAt k                     = iso (\(Int32Trie t) -> t) Int32Trie . at (fromEnum k)
  trieNull (Int32Trie x)        = IntMap.null x
  trieEmpty                    = Int32Trie IntMap.empty
  trieITraverse f (Int32Trie x) = fmap Int32Trie (reindexed (toEnum :: Int -> Int32) itraversed f x)
  trieAppend (Int32Trie x) (Int32Trie y) = Int32Trie (IntMap.unionWith (<>) x y)

instance TrieKey Int64 where
  newtype Trie Int64 a          = Int64Trie (Map Int64 a)
  trieAt k                      = iso (\(Int64Trie t) -> t) Int64Trie . at k
  trieNull (Int64Trie x)        = Map.null x
  trieEmpty                     = Int64Trie Map.empty
  trieITraverse f (Int64Trie x) = fmap Int64Trie (itraversed f x)
  trieAppend (Int64Trie x) (Int64Trie y) = Int64Trie (Map.unionWith (<>) x y)

instance TrieKey Word8 where
  newtype Trie Word8 a          = Word8Trie (IntMap a)
  trieAt k                      = iso (\(Word8Trie t) -> t) Word8Trie . at (fromEnum k)
  trieNull (Word8Trie x)        = IntMap.null x
  trieEmpty                     = Word8Trie IntMap.empty
  trieITraverse f (Word8Trie x) = fmap Word8Trie (reindexed (toEnum :: Int -> Word8) itraversed f x)
  trieAppend (Word8Trie x) (Word8Trie y) = Word8Trie (IntMap.unionWith (<>) x y)

instance TrieKey Word16 where
  newtype Trie Word16 a          = Word16Trie (IntMap a)
  trieAt k                       = iso (\(Word16Trie t) -> t) Word16Trie . at (fromEnum k)
  trieNull (Word16Trie x)        = IntMap.null x
  trieEmpty                      = Word16Trie IntMap.empty
  trieITraverse f (Word16Trie x) = fmap Word16Trie (reindexed (toEnum :: Int -> Word16) itraversed f x)
  trieAppend (Word16Trie x) (Word16Trie y) = Word16Trie (IntMap.unionWith (<>) x y)

instance TrieKey Word32 where
  newtype Trie Word32 a          = Word32Trie (Map Word32 a)
  trieAt k                       = iso (\(Word32Trie t) -> t) Word32Trie . at k
  trieNull (Word32Trie x)        = Map.null x
  trieEmpty                      = Word32Trie Map.empty
  trieITraverse f (Word32Trie x) = fmap Word32Trie (itraversed f x)
  trieAppend (Word32Trie x) (Word32Trie y) = Word32Trie (Map.unionWith (<>) x y)

instance TrieKey Word64 where
  newtype Trie Word64 a          = Word64Trie (Map Word64 a)
  trieAt k                       = iso (\(Word64Trie t) -> t) Word64Trie . at k
  trieNull (Word64Trie x)        = Map.null x
  trieEmpty                      = Word64Trie Map.empty
  trieITraverse f (Word64Trie x) = fmap Word64Trie (itraversed f x)
  trieAppend (Word64Trie x) (Word64Trie y) = Word64Trie (Map.unionWith (<>) x y)

instance TrieKey Integer where
  newtype Trie Integer a          = IntegerTrie (Map Integer a)
  trieAt k                        = iso (\(IntegerTrie t) -> t) IntegerTrie . at k
  trieNull (IntegerTrie x)        = Map.null x
  trieEmpty                       = IntegerTrie Map.empty
  trieITraverse f (IntegerTrie x) = fmap IntegerTrie (itraversed f x)
  trieAppend (IntegerTrie x) (IntegerTrie y) = IntegerTrie (Map.unionWith (<>) x y)

instance TrieKey Char where
  newtype Trie Char a          = CharTrie (IntMap a)
  trieAt k                     = iso (\(CharTrie t) -> t) CharTrie . at (ord k)
  trieNull (CharTrie x)        = IntMap.null x
  trieEmpty                    = CharTrie IntMap.empty
  trieITraverse f (CharTrie x) = fmap CharTrie (reindexed chr itraversed f x)
  trieAppend (CharTrie x) (CharTrie y) = CharTrie (IntMap.unionWith (<>) x y)

instance TrieKey Bool where
  data Trie Bool a              = BoolTrie !(Maybe a) !(Maybe a)
  trieAt False f (BoolTrie x y) = fmap (`BoolTrie` y) (f x)
  trieAt True  f (BoolTrie x y) = fmap (x `BoolTrie`) (f y)
  trieNull (BoolTrie x y)       = isNothing x && isNothing y
  trieEmpty                     = BoolTrie Nothing Nothing
  trieAppend (BoolTrie x1 x2) (BoolTrie y1 y2) = BoolTrie (x1 <> y1) (x2 <> y2)
  trieITraverse f (BoolTrie x y) = BoolTrie <$> traverse (indexed f False) x <*> traverse (indexed f True) y



instance TrieKey k => TrieKey (Maybe k) where
  newtype Trie (Maybe k) a = MaybeTrie (GenericTrie (Maybe k) a)

instance (TrieKey a, TrieKey b) => TrieKey (Either a b) where
  newtype Trie (Either a b) v = EitherTrie (GenericTrie (Either a b) v)

instance TrieKey () where
  newtype Trie () v = Tuple0Trie (GenericTrie () v)

instance (TrieKey a, TrieKey b) => TrieKey (a,b) where
  newtype Trie (a,b) v = Tuple2Trie (GenericTrie (a,b) v)

instance (TrieKey a, TrieKey b, TrieKey c) => TrieKey (a,b,c) where
  newtype Trie (a,b,c) v = Tuple3Trie (GenericTrie (a,b,c) v)

instance (TrieKey a, TrieKey b, TrieKey c, TrieKey d) => TrieKey (a,b,c,d) where
  newtype Trie (a,b,c,d) v = Tuple4Trie (GenericTrie (a,b,c,d) v)

instance (TrieKey a, TrieKey b, TrieKey c, TrieKey d, TrieKey e) => TrieKey (a,b,c,d,e) where
  newtype Trie (a,b,c,d,e) v = Tuple5Trie (GenericTrie (a,b,c,d,e) v)

instance (TrieKey a, TrieKey b, TrieKey c, TrieKey d, TrieKey e, TrieKey f) => TrieKey (a,b,c,d,e,f) where
  newtype Trie (a,b,c,d,e,f) v = Tuple6Trie (GenericTrie (a,b,c,d,e,f) v)

instance (TrieKey a, TrieKey b, TrieKey c, TrieKey d, TrieKey e, TrieKey f, TrieKey g) => TrieKey (a,b,c,d,e,f,g) where
  newtype Trie (a,b,c,d,e,f,g) v = Tuple7Trie (GenericTrie (a,b,c,d,e,f,g) v)

instance TrieKey Ordering where
  newtype Trie Ordering v = OrderingTrie (GenericTrie Ordering v)

instance TrieKey k => TrieKey [k] where
  newtype Trie [k] a = ListTrie (GenericTrie [k] a)


genericTrieNull ::
  forall k a.
  ( GTrieKey (Rep k)
  , Coercible (Trie k a) (GTrie (Rep k) a)
  ) =>
  Trie k a -> Bool
genericTrieNull = coerceWith (sym Coercion) (gtrieNull :: GTrie (Rep k) a -> Bool)

genericTrieEmpty ::
  forall k a.
  ( Generic k
  , GTrieKey (Rep k)
  , Coercible (Trie k a) (GTrie (Rep k) a)
  ) =>
  Trie k a
genericTrieEmpty = coerceWith (sym Coercion) (gtrieEmpty :: GTrie (Rep k) a)


genericTrieAppend ::
  forall k a.
  ( GTrieKey (Rep k)
  , Coercible (Trie k a) (GTrie (Rep k) a)
  , Semigroup a
  ) =>
  Trie k a -> Trie k a -> Trie k a
genericTrieAppend =
  case sym (Coercion :: Coercion (Trie k a) (GTrie (Rep k) a)) of
    Coercion ->
      Data.Coerce.coerce (gtrieAppend :: GTrie (Rep k) a -> GTrie (Rep k) a -> GTrie (Rep k) a)


genericTrieAt ::
  ( Generic k
  , GTrieKey (Rep k)
  , Coercible (Trie k a) (GTrie (Rep k) a)
  ) =>
  k -> Lens' (Trie k a) (Maybe a)
genericTrieAt k = iso Data.Coerce.coerce (coerceWith (sym Coercion)) . gtrieAt (GHC.Generics.from k)


genericTrieITraverse ::
  forall a b k.
  ( Generic k, GTrieKey (Rep k)
  , Coercible (Trie k b) (GTrie (Rep k) b)
  , Coercible (Trie k a) (GTrie (Rep k) a)) =>
  IndexedTraversal k (Trie k a) (Trie k b) a b
genericTrieITraverse = iso Data.Coerce.coerce (coerceWith (sym Coercion)) . reindexed to' gtrieITraverse
  where
  to' :: Rep k () -> k
  to' = GHC.Generics.to



-- | TrieKey operations on Generic representations used to provide
-- the default implementations of tries.
class GTrieKey f where
  data GTrie f a
  gtrieAt      :: f () -> Lens' (GTrie f a) (Maybe a)
  gtrieNull      :: GTrie f a -> Bool
  gtrieEmpty     :: GTrie f a
  gtrieAppend    :: Semigroup a => GTrie f a -> GTrie f a -> GTrie f a
  gtrieITraverse :: IndexedTraversal (f ()) (GTrie f a) (GTrie f b) a b



mtrieIso :: Iso (GTrie (M1 i c f) a) (GTrie (M1 i c f) b) (GTrie f a) (GTrie f b)
mtrieIso = iso (\(MTrie p) -> p) MTrie

instance GTrieKey f => GTrieKey (M1 i c f) where
  newtype GTrie (M1 i c f) a = MTrie (GTrie f a)
  gtrieAt (M1 k)             = mtrieIso . gtrieAt k
  gtrieNull (MTrie m)        = gtrieNull m
  gtrieEmpty                 = MTrie gtrieEmpty
  gtrieAppend (MTrie x) (MTrie y) = MTrie (gtrieAppend x y)
  gtrieITraverse             = mtrieIso . reindexed m1 gtrieITraverse
    where
    m1 :: f () -> M1 i c f ()
    m1 = M1


ktrieIso :: Iso (GTrie (K1 i k) a) (GTrie (K1 i k') b) (Trie k a) (Trie k' b)
ktrieIso = iso (\(KTrie p) -> p) KTrie

instance TrieKey k => GTrieKey (K1 i k) where
  newtype GTrie (K1 i k) a = KTrie (Trie k a)
  gtrieAt (K1 k)           = ktrieIso . trieAt k
  gtrieNull (KTrie k)      = trieNull k
  gtrieEmpty               = KTrie trieEmpty
  gtrieAppend (KTrie x) (KTrie y) = KTrie (trieAppend x y)
  gtrieITraverse           = ktrieIso . reindexed k1 trieITraverse
    where
    k1 :: a -> K1 i a ()
    k1 = K1


ptrieIso :: Iso (GTrie (f :*: g) a) (GTrie (f' :*: g') b) (GTrie f (GTrie g a)) (GTrie f' (GTrie g' b))
ptrieIso = iso (\(PTrie p) -> p) PTrie

instance (GTrieKey f, GTrieKey g) => GTrieKey (f :*: g) where
  newtype GTrie (f :*: g) a = PTrie (GTrie f (GTrie g a))

  gtrieAt (i :*: j)   = ptrieIso
                      . gtrieAt i
                      . anon gtrieEmpty gtrieNull
                      . gtrieAt j

  gtrieEmpty          = PTrie gtrieEmpty
  gtrieAppend (PTrie x) (PTrie y) = PTrie (x <> y)
  gtrieNull (PTrie m) = gtrieNull m
  gtrieITraverse      = ptrieIso . icompose (:*:) gtrieITraverse gtrieITraverse


-- Actually used in the :*: case's gtrieAppend!
instance (GTrieKey k, Semigroup a) => Semigroup (GTrie k a) where
  (<>) = gtrieAppend


strieFst :: Lens (GTrie (f :+: g) a) (GTrie (f' :+: g) a) (GTrie f a) (GTrie f' a)
strieFst f (STrie a b) = fmap (`STrie` b) (f a)

strieSnd :: Lens (GTrie (f :+: g) a) (GTrie (f :+: g') a) (GTrie g a) (GTrie g' a)
strieSnd f (STrie a b) = fmap (a `STrie`) (f b)

instance (GTrieKey f, GTrieKey g) => GTrieKey (f :+: g) where

  data GTrie (f :+: g) a       = STrie !(GTrie f a) !(GTrie g a)
  gtrieAt (L1 k)               = strieFst . gtrieAt k
  gtrieAt (R1 k)               = strieSnd . gtrieAt k
  gtrieEmpty                   = STrie gtrieEmpty gtrieEmpty
  gtrieNull (STrie m1 m2)      = gtrieNull m1 && gtrieNull m2
  gtrieAppend (STrie m1 m2) (STrie n1 n2) = STrie (gtrieAppend m1 n1) (gtrieAppend m2 n2)
  gtrieITraverse f (STrie x y) = STrie <$> reindexed l1 gtrieITraverse f x
                                       <*> reindexed r1 gtrieITraverse f y
    where
    l1 :: f () -> (f :+: g) ()
    l1 = L1
    r1 :: g () -> (f :+: g) ()
    r1 = R1


utrieIso :: Iso (GTrie U1 a) (GTrie U1 b) (Maybe a) (Maybe b)
utrieIso = iso (\(UTrie x) -> x) UTrie

instance GTrieKey U1 where
  newtype GTrie U1 a  = UTrie (Maybe a)
  gtrieAt _           = utrieIso
  gtrieEmpty          = UTrie Nothing
  gtrieNull (UTrie u) = isNothing u
  gtrieAppend (UTrie x) (UTrie y) = UTrie (x <> y)
  gtrieITraverse      = utrieIso . traverse . flip indexed u1
    where
    u1 :: U1 ()
    u1 = U1


instance GTrieKey V1 where
  data GTrie V1 a        = VTrie
  gtrieAt k _ _          = k `seq` error "GTrieKey.V1: gtrieAt"
  gtrieEmpty             = VTrie
  gtrieAppend _ _        = VTrie
  gtrieNull _            = True
  gtrieITraverse _ _     = pure VTrie


instance TrieKey k => FunctorWithIndex     k (Trie k) where
instance TrieKey k => FoldableWithIndex    k (Trie k) where
instance TrieKey k => TraversableWithIndex k (Trie k) where
  itraverse  = trieITraverse . Indexed
  itraversed = trieITraverse

instance (Eq a, TrieKey k) => Eq (Trie k a) where
  x == y = Foldable.all isGoodMatch (start x <> start y)
    where
    start = fmap (\x -> [x])

    isGoodMatch [a,b] = a == b
    isGoodMatch _     = False
