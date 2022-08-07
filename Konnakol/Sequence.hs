{-
    Sequence.hs - core representation of Tidal sequences
    Copyright (C) 2022 Alex McLean and contributors

    This library is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this library.  If not, see <http://www.gnu.org/licenses/>.
-}

module Sequence where

import Data.List(inits)
import Prelude hiding (span)
import Data.Ratio
import Sound.Tidal.Bjorklund
import Konnakol.Define

data Strategy = JustifyLeft
              | JustifyRight
              | JustifyBoth
              | Expand
              | TruncateMax
              | TruncateMin
              | RepeatLCM
              | Centre
              | Squeeze
              deriving Show

data Sequence a = Atom Rational a
                | Gap Rational
                | Sequence [Sequence a]
                | Stack [Sequence a]
              deriving Show

instance Functor Sequence where
  fmap f (Atom x y) = Atom x (f y)
  fmap _ (Gap x) = Gap x
  fmap f (Sequence x) = Sequence $ map (fmap f) x
  fmap f (Stack y) = Stack (map (fmap f) y)


instance Applicative Sequence where
  pure x = Atom 1 x
  (Atom x f) <*> something =
    let (p,q) = forTwo (Atom x f) something
        c = reAlign p q
        d = unwrap $ Sequence $ map (fmap f) c
    in d
  Gap x <*> something =
    let (p,_) = forTwo (Gap x) something
    in unwrap $ Sequence  p
  Sequence f <*> something =
    let (p,q) = forTwo (Sequence f) something
        c = unwrapper $ reAlign p q
        d = unwrap $ Sequence  $ funcMap p c
    in d
  Stack f <*> something =
    let d = map (<*> something) f
    in Stack d

instance Monad Sequence where
  return x = Atom 1 x
  Atom _ y >>= f = f y
  Gap x >>= _ = Gap x
  Sequence x >>= f = Sequence $ map (>>= f) x
  Stack y >>= f = Stack (map (>>= f) y)

-- | Takes sequence of functions and a sequence which have been aligned and applies the functions at the corresponding time points
funcMap :: [Sequence (a->b)] -> [Sequence a] -> [Sequence b]
funcMap [] _ = []
funcMap ((Atom x f):xs) y =
  let t = seqSpan (Atom x f)
      p = takeWhile (\r -> sum(map seqSpan r) <= t) $ inits y
      pTill = last p
      q = map (fmap f) pTill
  in q ++ funcMap xs (drop (length pTill) y)
funcMap (Gap x:xs) y=
  let t = seqSpan (Gap x)
      p = takeWhile (\r -> sum(map seqSpan r) <= t) $ inits y
      pTill = last p
      q = Gap (sum $ map seqSpan pTill)
  in q : funcMap xs (drop (length pTill) y)
funcMap (Sequence x:xs) y = funcMap (unwrapper x ++ xs) y
funcMap _ _ = error "funcMap cannot be called on stack"

-- | Mapping a function on entire sequence instead of just the values it takes
map' :: (Sequence a1 -> Sequence a2) -> Sequence a1 -> Sequence a2
map' f (Atom x y) = f (Atom x y)
map' f (Gap x) = f (Gap x)
map' f (Sequence x) = Sequence $ map (map' f) x
map' f (Stack y) = Stack (map (map' f) y)

-- | Function to map a seqeuence of a functions on another sequence
mapSeq::Sequence (Sequence a-> Sequence b) -> Sequence a -> Sequence b
mapSeq (Atom x f) something =
  let (p,q) = forTwo (Atom x f) something
      c = reAlign p q
      d = unwrap $ Sequence $ map (map' f) c
  in d
mapSeq (Gap x) something =
  let (p,_) = forTwo (Gap x) something
  in unwrap $ Sequence  p
mapSeq (Sequence f) something =
    let (p,q) = forTwo (Sequence f) something
        c = unwrapper $ reAlign p q
        d = unwrap $ Sequence  $ funcSeq p c
    in d
mapSeq (Stack f) something =
    let d = map (`mapSeq` something) f
    in Stack d

-- | Takes sequence of functions on sequences and a sequence which have been aligned and applies the functions at 
-- the corresponding time points
funcSeq :: [Sequence (Sequence a1 -> Sequence a2)]-> [Sequence a1] -> [Sequence a2]
funcSeq [] _ = []
funcSeq ((Atom x f):xs) y =
  let t = seqSpan (Atom x f)
      p = takeWhile (\r -> sum(map seqSpan r) <= t) $ inits y
      pTill = last p
      q = map (map' f) pTill
  in q ++ funcSeq xs (drop (length pTill) y)
funcSeq (Gap x:xs) y=
  let t = seqSpan (Gap x)
      p = takeWhile (\r -> sum(map seqSpan r) <= t) $ inits y
      pTill = last p
      q = Gap (sum $ map seqSpan pTill)
  in q : funcSeq xs (drop (length pTill) y)
funcSeq (Sequence x:xs) y = funcSeq (unwrapper x ++ xs) y
funcSeq _ _ = error "funcSeq cannot be called on Stack"

-- | Takes two sequences, which have been obtained using stratApply, or forTwo, and then splits the second sequence with respect
-- to the break points of the first
reAlign:: [Sequence a] -> [Sequence b] -> [Sequence b]
reAlign [] _ = []
reAlign ((Gap x):xs) y =
  let t = seqSpan (Gap x)
      p  = takeWhile (\q -> sum (map seqSpan q) <=t ) $ inits y
      pTill = last p
      l = length pTill
      tTill = sum (map seqSpan pTill)
      (a,b) = if tTill == t then (Gap 0, drop l y)  else
        let (m,n) =  getPartition (y!!l) (t - tTill)
        in (m, n :drop (l+1) y)
  in if tTill == t then pTill ++ reAlign xs b else (pTill ++ [a]) ++ reAlign xs b
reAlign ((Atom x s):xs) y =
  let t = seqSpan (Atom x s)
      p  = takeWhile (\q -> sum (map seqSpan q) <=t ) $ inits y
      pTill = last p
      l = length pTill
      tTill = sum (map seqSpan pTill)
      (a,b) = if tTill == t then (Gap 0, drop l y)  else
        let (m,n) =  getPartition (y!!l) (t - tTill)
        in (m, n :drop (l+1) y)
  in (pTill ++ [a]) ++ reAlign xs b
reAlign (Sequence x:xs) (Sequence y:ys) = reAlign (unwrapper x ++ xs) (unwrapper y ++ ys)
reAlign _ _ = error "reAlign not defined"


-- | Function to partition an event in a sequence
getPartition::Sequence a-> Rational -> (Sequence a, Sequence a)
getPartition (Atom x s) t = (Atom t s, Atom (x-t) s)
getPartition (Gap x) t = (Gap t, Gap (x - t))
getPartition (Sequence y) t =
  let p = takeWhile (\q -> sum (map seqSpan q) <=t ) $ inits y
      pTill = last p
      l = length pTill
      tTill = sum (map seqSpan pTill)
      (a,b) = if tTill == t then (Gap 0, drop l y)  else
        let (m,n) =  getPartition (y!!l) (t - tTill)
        in (m, n :drop (l+1) y)
  in (Sequence $ pTill ++ [a], Sequence b)
getPartition (Stack s) t = let a = map (`getPartition` t) s in (Stack (map fst a),Stack (map snd a))

-- | Given two sequences of different types, this function uses the LCM method to align those two sequences
forTwo :: Sequence a1 -> Sequence a2 -> ([Sequence a1], [Sequence a2])
forTwo a b =
  let p = lcmRational (seqSpan a) (seqSpan b)
  in (unwrapper $ replicate (fromIntegral  $ numerator $ p/seqSpan a) a, unwrapper $ replicate (fromIntegral $ numerator $ p/seqSpan b) b)

unwrap::Sequence a -> Sequence a
unwrap (Sequence x) = Sequence $  unwrapper x
unwrap (Stack x) = Stack $ map unwrap x
unwrap s = s

-- | Unwrapping a sequence referes to removing the redundancies that are present in the code
unwrapper:: [Sequence a] -> [Sequence a]
unwrapper [] = []
unwrapper [Sequence x] = unwrapper x
unwrapper (Sequence x :xs) = unwrapper x ++ unwrapper xs
unwrapper (Atom x s:xs) = Atom x s : unwrapper xs
unwrapper (Gap x:xs) = if x ==0 then unwrapper xs else Gap x: unwrapper xs
unwrapper (Stack x:xs) = Stack x : unwrapper xs

rev :: Sequence a -> Sequence a
rev (Sequence bs) = Sequence $ reverse $ map rev bs
rev (Stack bs) = Stack $ map rev bs
rev b = b

cat :: [Sequence a] -> Sequence a
cat [] = Gap 0
cat [b] = b
cat bs = Sequence bs

ply :: Int -> Sequence a -> Sequence a
ply n (Atom d v) = Sequence $ replicate n $ Atom (d / toRational n) v
ply n (Gap x) = Sequence $ replicate n $ Gap (x/ toRational n)
ply n (Sequence x) = unwrap $ Sequence (map (ply n) x)
ply n (Stack x) =  Stack (map (ply n) x)

seqSpan :: Sequence a -> Rational
seqSpan (Atom s _) = s
seqSpan (Gap s) = s
seqSpan (Sequence bs) = sum $ map seqSpan bs
seqSpan (Stack []) = 0
seqSpan (Stack x) = seqSpan $ head x

lcmRational :: Rational->Rational-> Rational
lcmRational a b = lcm (f a) (f b) % d
  where d = lcm (denominator a) (denominator b)
        f x = numerator x * (d `div` denominator x)

-- | stratApply takes a list of sequences, a strategy, and then aligns all those sequences according to these strategies
stratApply::Strategy -> [Sequence a] ->Sequence a
stratApply _ [] = Gap 0

stratApply JustifyLeft bs =
  let a = maximum $ map seqSpan bs
      b = map (\x -> Sequence (x: [Gap (a - seqSpan x)])) bs
  in Stack b

stratApply JustifyRight bs =
  let a = maximum $ map seqSpan bs
      b = map (\x -> Sequence (Gap (a - seqSpan x) : [x])) bs
  in Stack b

stratApply Centre bs =
  let a = maximum $ map seqSpan bs
      b = map( \x -> Sequence ([Gap ((a - seqSpan x)/2)] ++ [x] ++ [Gap ((a - seqSpan x)/2)])) bs
  in Stack b

stratApply RepeatLCM bs@(x:xs) =
  let a = foldr (lcmRational . seqSpan) (seqSpan x) xs
      b = map (\r ->  unwrap $ Sequence $  replicate (fromIntegral $ numerator $ a/seqSpan r) x) bs
  in Stack b

stratApply Expand bs =
  let a = maximum $ map seqSpan bs
      b = map (\x -> expand x $ a/seqSpan x) bs
  in Stack b

stratApply Squeeze bs =
  let a = minimum $ map seqSpan bs
      b = map (\x -> expand x $ a/seqSpan x) bs
  in Stack b

stratApply JustifyBoth bs =
  let a = maximum $ map seqSpan bs
      b = map (`expand'` a) bs
  in Stack b

stratApply TruncateMin bs =
  let a = minimum $ map seqSpan bs
      b = map (`cutShort` a) bs
  in Stack b

stratApply TruncateMax bs =
  let a = maximum $ map seqSpan bs
      b = map (\x -> unwrap $ Sequence $ replicate (floor $ a/seqSpan x) x ++ let Sequence p = cutShort x (realToFrac (a - floor (a/seqSpan x)%1 * seqSpan x)) in p) bs
  in Stack b

-- Return a segment of a sequence
cutShort::Sequence a->Rational->Sequence a
cutShort (Atom x s) r = if x>r then Atom r s else Atom x s
cutShort (Gap x) r = if x > r then Gap r else Gap x
cutShort (Sequence x) r =
  let p = takeWhile (\q -> sum (map seqSpan q) <=r ) $ inits x
      pTill = last p
      l = length pTill
      tTill = sum (map seqSpan pTill)
  in if tTill == r then Sequence pTill else Sequence $ pTill ++ [fst (getPartition (x!!l) (r - tTill))]
cutShort (Stack x) r = Stack $ map (`cutShort` r) x

-- | Expand a sequence to a particular length, while not modifying the length of that sequence
expand'::Sequence a -> Rational -> Sequence a
expand' (Atom x s) r = expand (Atom x s) $ r/seqSpan (Atom x s)
expand' (Gap x) r = expand (Gap x) $ r/seqSpan (Gap x)
expand' (Sequence [x]) r = Sequence [expand x (r/seqSpan x)]
expand' (Sequence x) r =
  let Sequence y = (expand (Sequence $ init x) $ (r- seqSpan (last x))/ seqSpan (Sequence $ init x))
  in Sequence (y++ [last x])
expand' (Stack x) r = Stack $ map (`expand'` r) x

-- | Expand a sequence to a particular length
expand::Sequence a-> Rational -> Sequence a
expand (Atom x s) r = Atom (x*r) s
expand (Gap x) r = Gap (x*r)
expand (Sequence x) r = Sequence $ map (`expand` r) x
expand (Stack x) r = Stack $ map (`expand` r) x


-- | Reduce a list of sequences by removing redundancies
reduce::Eq a=>[Sequence a] -> [Sequence a]
reduce ((Atom x1 s1):(Atom x2 s2):xs) = if s1==s2 then reduce $ Atom (x1+x2) s1:xs else Atom x1 s1:reduce ( Atom x2 s2:  xs)
reduce (Gap x1:Gap x2:xs) =reduce $ Gap (x1+x2):xs
reduce (Sequence x:xs) = Sequence (reduce x):reduce xs
reduce (Stack x:xs) = Stack (reduce x):reduce xs
reduce (x:xs) = x:reduce xs
reduce [] = []

applyfToSeq :: (t -> a) -> Sequence t -> Sequence a
applyfToSeq f (Atom x s) = Atom x (f s)
applyfToSeq _ (Gap x) = Gap x
applyfToSeq f (Sequence x) = Sequence $ map (applyfToSeq f) x
applyfToSeq f (Stack x) = Stack $ map (applyfToSeq f) x

-- | Speed up the sequence
fast :: Sequence Rational -> Sequence a -> Sequence a
fast sr s = mapSeq (applyfToSeq _fast sr) s

_fast :: Rational -> Sequence a -> Sequence a
_fast n (Atom x s) = Atom (x/n) s
_fast n (Gap x) = Gap (x/n)
_fast n (Sequence s) = Sequence $ map (_fast n) s
_fast n (Stack x) = Stack $ map(_fast n) x

-- | Slow down the sequence
slow::Sequence Rational->Sequence a->Sequence a
slow sr s = mapSeq (applyfToSeq _slow sr) s

_slow::Rational -> Sequence a -> Sequence a
_slow n = _fast (1/n)

-- | Repeat the sequence a desired number of times without changing duration
rep::Eq a=>Int -> Sequence a-> Sequence a
rep n (Atom x s) = Atom (realToFrac n * x) s
rep n (Gap x) = Gap (realToFrac  n*x)
rep n (Sequence s) = Sequence $ reduce $  concat $ replicate n s
rep n (Stack s) = Stack $ map (rep n) s

-- | Repeat sequence desired number of times, and squeeze it into the duration of the original sequence
repSqueeze::Eq a=>Int -> Sequence a-> Sequence a
repSqueeze n s = _fast (realToFrac n) $ rep n s

-- | Takes a list of sequences, and if aligned returns a stack. Otherwise applies default method and returns
stack::[Sequence a] -> Sequence a
stack s =
  let a = foldl (\acc x->if seqSpan x==acc then acc else -1) (seqSpan $ head s) s
  in if a == (-1) then stratApply Expand s else Stack s

-- | Obtain a euclidean pattern 
_euclid::Int-> Int-> Sequence a -> Sequence a
_euclid a b s  =
  let x = bjorklund (a, b)
      y = map (\t -> if t then s else Gap (seqSpan s)) x
  in unwrap $ Sequence y


{-
   EXISTING STUFF IN TIDAL
   Method for showing
   < > Plays one among for each iteration
   every method
   
   -}

{-
  New stuff that I would like to add
  * Method which takes an integer and splits sequence recursively at those intervals (fitToTime)
  * 
-}
