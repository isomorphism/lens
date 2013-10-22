{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
------------------------------------------------------------------------------
-- |
-- Module      :  Control.Lens.Reified
-- Copyright   :  (C) 2012-13 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  provisional
-- Portability :  Rank2Types
--
------------------------------------------------------------------------------
module Control.Lens.Reified where

import Control.Applicative
import Control.Arrow
import qualified Control.Category as Cat
import Control.Comonad
import Control.Lens.Fold
import Control.Lens.Getter
import Control.Lens.Traversal (ignored)
import Control.Lens.Type
import Control.Monad
import Control.Monad.Reader.Class
import Data.Profunctor
import Data.Monoid

------------------------------------------------------------------------------
-- Lens
------------------------------------------------------------------------------

-- | Reify a 'Lens' so it can be stored safely in a container.
newtype ReifiedLens s t a b = Lens { runLens :: Lens s t a b }

-- | @
-- type 'ReifiedLens'' = 'Simple' 'ReifiedLens'
-- @
type ReifiedLens' s a = ReifiedLens s s a a

------------------------------------------------------------------------------
-- IndexedLens
------------------------------------------------------------------------------

-- | Reify an 'IndexedLens' so it can be stored safely in a container.
newtype ReifiedIndexedLens i s t a b = IndexedLens { runIndexedLens :: IndexedLens i s t a b }

-- | @
-- type 'ReifiedIndexedLens'' i = 'Simple' ('ReifiedIndexedLens' i)
-- @
type ReifiedIndexedLens' i s a = ReifiedIndexedLens i s s a a

------------------------------------------------------------------------------
-- IndexedTraversal
------------------------------------------------------------------------------

-- | Reify an 'IndexedTraversal' so it can be stored safely in a container.
newtype ReifiedIndexedTraversal i s t a b = IndexedTraversal { runIndexedTraversal :: IndexedTraversal i s t a b }

-- | @
-- type 'ReifiedIndexedTraversal'' i = 'Simple' ('ReifiedIndexedTraversal' i)
-- @
type ReifiedIndexedTraversal' i s a = ReifiedIndexedTraversal i s s a a

------------------------------------------------------------------------------
-- Traversal
------------------------------------------------------------------------------

-- | A form of 'Traversal' that can be stored monomorphically in a container.
newtype ReifiedTraversal s t a b = Traversal { runTraversal :: Traversal s t a b }

-- | @
-- type 'ReifiedTraversal'' = 'Simple' 'ReifiedTraversal'
-- @
type ReifiedTraversal' s a = ReifiedTraversal s s a a

------------------------------------------------------------------------------
-- Getter
------------------------------------------------------------------------------

-- | Reify a 'Getter' so it can be stored safely in a container.
--
-- This can also be useful when combining getters in novel ways, as
-- 'ReifiedGetter' is isomorphic to '(->)' and provides similar instances.
--
-- >>> ("hello","world","!!!")^.runGetter ((,) <$> Getter _2 <*> Getter (_1.to length))
-- ("world",5)
newtype ReifiedGetter s a = Getter { runGetter :: Getter s a }

instance Functor (ReifiedGetter s) where
  fmap f l = Getter (runGetter l.to f)

instance Monoid s => Comonad (ReifiedGetter s) where
  extract (Getter l) = view l mempty
  duplicate (Getter l) = Getter $ to $ \m -> Getter $ to $ \n -> view l (mappend m n)

instance Applicative (ReifiedGetter s) where
  pure a = Getter $ to $ \_ -> a
  Getter mf <*> Getter ma = Getter $ to $ \s -> view mf s (view ma s)

instance Monad (ReifiedGetter s) where
  return a = Getter $ to $ \_ -> a
  Getter ma >>= f = Getter $ to $ \s -> view (runGetter (f (view ma s))) s

instance MonadReader s (ReifiedGetter s) where
  ask = Getter id
  local f m = Getter (to f . runGetter m)

instance Profunctor ReifiedGetter where
  dimap f g l = Getter $ to f.runGetter l.to g
  lmap g l    = Getter $ to g.runGetter l
  rmap f l    = Getter $ runGetter l.to f

instance Strong ReifiedGetter where
  first' l  = Getter $ to $ first' $ view $ runGetter l
  second' l = Getter $ to $ second' $ view $ runGetter l

instance Choice ReifiedGetter where
  left' l = Getter $ to $ left' $ view $ runGetter l
  right' l = Getter $ to $ right' $ view $ runGetter l

instance Cat.Category ReifiedGetter where
  id = Getter id
  l . r = Getter (runGetter r.runGetter l)

instance Arrow ReifiedGetter where
  arr f = Getter (to f)
  first l = Getter $ to $ first $ view $ runGetter l
  second l = Getter $ to $ second $ view $ runGetter l
  Getter l *** Getter r = Getter $ to $ view l *** view r
  Getter l &&& Getter r = Getter $ to $ view l &&& view r

instance ArrowApply ReifiedGetter where
  app = Getter $ to $ \(Getter bc, b) -> view bc b

instance ArrowChoice ReifiedGetter where
  left l = Getter $ to $ left $ view $ runGetter l
  right l = Getter $ to $ right $ view $ runGetter l
  Getter l +++ Getter r = Getter $ to $ view l +++ view r
  Getter l ||| Getter r = Getter $ to $ view l ||| view r

instance ArrowLoop ReifiedGetter where
  loop l = Getter $ to $ loop $ view $ runGetter l

------------------------------------------------------------------------------
-- IndexedGetter
------------------------------------------------------------------------------

-- | Reify an 'IndexedGetter' so it can be stored safely in a container.
newtype ReifiedIndexedGetter i s a = IndexedGetter { runIndexedGetter :: IndexedGetter i s a }

instance Profunctor (ReifiedIndexedGetter i) where
  dimap f g l = IndexedGetter (to f . runIndexedGetter l . to g)

instance Strong (ReifiedIndexedGetter i) where
  first' l = IndexedGetter $ \f (s,c) ->
    coerce $ runIndexedGetter l (dimap (flip (,) c) coerce f) s
  second' l = IndexedGetter $ \f (c,s) ->
    coerce $ runIndexedGetter l (dimap ((,) c) coerce f) s

instance Functor (ReifiedIndexedGetter i s) where
  fmap f l = IndexedGetter (runIndexedGetter l.to f)

------------------------------------------------------------------------------
-- Fold
------------------------------------------------------------------------------

-- | Reify a 'Fold' so it can be stored safely in a container.
--
-- This can also be useful for creatively combining folds as
-- @'ReifiedFold' s@ is isomorphic to @ReaderT s []@ and provides similar
-- instances.
--
-- >>> ("hello","world")^..runFold ((,) <$> Fold _2 <*> Fold both)
-- [("world","hello"),("world","world")]
newtype ReifiedFold s a = Fold { runFold :: Fold s a }

instance Profunctor ReifiedFold where
  dimap f g l = Fold (to f . runFold l . to g)
  rmap g l = Fold (runFold l . to g)
  lmap f l = Fold (to f . runFold l)

instance Strong ReifiedFold where
  first' (Fold l) = Fold $ folding $ \(s,c) -> fmap (\s' -> (s', c)) (toListOf l s)
  second' (Fold l) = Fold $ folding $ \(c,s) -> (,) c <$> toListOf l s

instance Choice ReifiedFold where
  left' (Fold l) = Fold $ folding $ \esc -> case esc of
    Left s -> Left <$> toListOf l s
    Right c -> [Right c]
  right' (Fold l) = Fold $ folding $ \ecs -> case ecs of
    Left c -> [Left c]
    Right s -> Right <$> toListOf l s

instance Cat.Category ReifiedFold where
  id = Fold id
  l . r = Fold (runFold r . runFold l)

instance Arrow ReifiedFold where
  arr f = Fold (to f)
  first = first'
  second = second'
  Fold l *** Fold r = Fold $ folding $ \(x,y) -> (,) <$> toListOf l x <*> toListOf r y
  Fold l &&& Fold r = Fold $ folding $ \x -> (,) <$> toListOf l x <*> toListOf r x

instance ArrowChoice ReifiedFold where
  left = left'
  right = right'

instance ArrowApply ReifiedFold where
  app = Fold $ folding $ \(Fold bc, b) -> toListOf bc b

instance Functor (ReifiedFold s) where
  fmap f l = Fold (runFold l.to f)

instance Applicative (ReifiedFold s) where
  pure a = Fold $ folding $ \_ -> [a]
  Fold mf <*> Fold ma = Fold $ folding $ \s -> toListOf mf s <*> toListOf ma s

instance Alternative (ReifiedFold s) where
  empty = Fold ignored
  Fold ma <|> Fold mb = Fold $ folding (\s -> toListOf ma s ++ toListOf mb s)

instance Monad (ReifiedFold s) where
  return a = Fold $ folding $ \_ -> [a]
  Fold ma >>= f = Fold $ folding $ \s -> toListOf ma s >>= \a -> toListOf (runFold (f a)) s

instance MonadPlus (ReifiedFold s) where
  mzero = empty
  mplus = (<|>)

instance MonadReader s (ReifiedFold s) where
  ask = Fold $ folding $ \s -> [s]
  local f m = Fold (to f . runFold m)

------------------------------------------------------------------------------
-- IndexedFold
------------------------------------------------------------------------------

newtype ReifiedIndexedFold i s a = IndexedFold { runIndexedFold :: IndexedFold i s a }

instance Functor (ReifiedIndexedFold i s) where
  fmap f l = IndexedFold (runIndexedFold l . to f)

instance Profunctor (ReifiedIndexedFold i) where
  dimap f g l = IndexedFold (to f . runIndexedFold l . to g)
  lmap f l = IndexedFold (to f . runIndexedFold l)
  rmap g l = IndexedFold (runIndexedFold l . to g)

instance Strong (ReifiedIndexedFold i) where
  first' l  = IndexedFold $ \f (s,c) ->
    coerce $ runIndexedFold l (dimap (flip (,) c) coerce f) s
  second' l = IndexedFold $ \f (c,s) ->
    coerce $ runIndexedFold l (dimap ((,) c) coerce f) s

------------------------------------------------------------------------------
-- Setter
------------------------------------------------------------------------------

-- | Reify a 'Setter' so it can be stored safely in a container.
newtype ReifiedSetter s t a b = Setter { runSetter :: Setter s t a b }

-- | @
-- type 'ReifiedSetter'' = 'Simple' 'ReifiedSetter'
-- @
type ReifiedSetter' s a = ReifiedSetter s s a a

------------------------------------------------------------------------------
-- IndexedSetter
------------------------------------------------------------------------------

-- | Reify an 'IndexedSetter' so it can be stored safely in a container.
newtype ReifiedIndexedSetter i s t a b =
  IndexedSetter { runIndexedSetter :: IndexedSetter i s t a b }

-- | @
-- type 'ReifiedIndexedSetter'' i = 'Simple' ('ReifiedIndexedSetter' i)
-- @
type ReifiedIndexedSetter' i s a = ReifiedIndexedSetter i s s a a

------------------------------------------------------------------------------
-- Iso
------------------------------------------------------------------------------

-- | Reify an 'Iso' so it can be stored safely in a container.
newtype ReifiedIso s t a b = Iso { runIso :: Iso s t a b }

-- | @
-- type 'ReifiedIso'' = 'Simple' 'ReifiedIso'
-- @
type ReifiedIso' s a = ReifiedIso s s a a

------------------------------------------------------------------------------
-- Prism
------------------------------------------------------------------------------

-- | Reify a 'Prism' so it can be stored safely in a container.
newtype ReifiedPrism s t a b = Prism { runPrism :: Prism s t a b }

-- | @
-- type 'ReifiedPrism'' = 'Simple' 'ReifiedPrism'
-- @
type ReifiedPrism' s a = ReifiedPrism s s a a
