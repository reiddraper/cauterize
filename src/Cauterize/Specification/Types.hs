{-# LANGUAGE FlexibleInstances, RecordWildCards, DeriveDataTypeable, OverloadedStrings #-}
module Cauterize.Specification.Types
  ( Spec(..)
  , SpType(..)
  , Sized(..)

  , FixedSize(..)
  , RangeSize(..)

  , LengthRepr(..)
  , TagRepr(..)
  , FlagsRepr(..)

  , Depth(..)
  , TypeTagWidth(..)
  , LengthTagWidth(..)

  , fromSchema
  , prettyPrint
  , typeName
  , specTypeMap
  , specTypeTagMap
  , typeDepthMap
  ) where

import Cauterize.FormHash
import Cauterize.Common.Types
import Data.List
import Data.Function
import Data.Maybe
import Data.Graph
import Data.Data
import Data.Word

import qualified Cauterize.Common.Types as CT
import qualified Cauterize.Schema.Types as SC
import qualified Data.ByteString as B
import qualified Data.List as L
import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.Text.Lazy as T

import Text.PrettyPrint.Leijen.Text

data FixedSize = FixedSize { unFixedSize :: Integer }
  deriving (Show, Ord, Eq, Data, Typeable)
data RangeSize = RangeSize { rangeSizeMin :: Integer, rangeSizeMax :: Integer }
  deriving (Show, Ord, Eq, Data, Typeable)

data LengthRepr = LengthRepr { unLengthRepr :: BuiltIn }
  deriving (Show, Ord, Eq, Data, Typeable)
data TagRepr = TagRepr { unTagRepr :: BuiltIn }
  deriving (Show, Ord, Eq, Data, Typeable)
data FlagsRepr = FlagsRepr { unFlagsRepr :: BuiltIn }
  deriving (Show, Ord, Eq, Data, Typeable)

newtype Depth = Depth { unDepth :: Integer }
  deriving (Show, Ord, Eq, Data, Typeable)

newtype LengthTagWidth = LengthTagWidth { unLengthTagWidth :: Integer }
  deriving (Show, Ord, Eq, Data, Typeable)

newtype TypeTagWidth = TypeTagWidth { unTypeTagWidth :: Integer }
  deriving (Show, Ord, Eq, Data, Typeable)

mkRangeSize :: Integer -> Integer -> RangeSize
mkRangeSize mi ma = if mi > ma
                      then error $ "Bad range: " ++ show mi ++ " -> " ++ show ma ++ "."
                      else RangeSize mi ma

class Sized a where
  minSize :: a -> Integer
  maxSize :: a -> Integer

  minimumOfSizes :: [a] -> Integer
  minimumOfSizes [] = 0
  minimumOfSizes xs = minimum $ map minSize xs

  maximumOfSizes :: [a] -> Integer
  maximumOfSizes [] = 0
  maximumOfSizes xs = maximum $ map maxSize xs

  rangeFitting :: [a] -> RangeSize
  rangeFitting ss = mkRangeSize (minimumOfSizes ss) (maximumOfSizes ss)

  sumOfMinimums :: [a] -> Integer
  sumOfMinimums = sum . map minSize

  sumOfMaximums :: [a] -> Integer
  sumOfMaximums = sum . map maxSize

instance Sized FixedSize where
  minSize (FixedSize i) = i
  maxSize (FixedSize i) = i

instance Sized RangeSize where
  minSize (RangeSize i _) = i
  maxSize (RangeSize _ i) = i

instance Pretty FixedSize where
  pretty (FixedSize s) = parens $ text "fixed-size" <+> integer s

instance Pretty RangeSize where
  pretty (RangeSize mi ma) = parens $ text "range-size" <+> integer mi <+> integer ma

instance Pretty LengthRepr where
  pretty (LengthRepr bi) = parens $ text "length-repr" <+> pShow bi

instance Pretty TagRepr where
  pretty (TagRepr bi) = parens $ text "tag-repr" <+> pShow bi

instance Pretty FlagsRepr where
  pretty (FlagsRepr bi) = parens $ text "flags-repr" <+> pShow bi

instance Pretty Depth where
  pretty (Depth d) = parens $ text "depth" <+> integer d

instance Pretty TypeTagWidth where
  pretty (TypeTagWidth d) = parens $ text "type-width" <+> integer d

instance Pretty LengthTagWidth where
  pretty (LengthTagWidth d) = parens $ text "length-width" <+> integer d

data Spec = Spec { specName :: Name
                 , specVersion :: Version
                 , specHash :: FormHash
                 , specSize :: RangeSize
                 , specDepth :: Depth
                 , specTypeTagWidth :: TypeTagWidth
                 , specLengthTagWidth :: LengthTagWidth
                 , specTypes :: [SpType] }
  deriving (Show, Eq, Data, Typeable)

data SpType = BuiltIn      { unBuiltIn   :: TBuiltIn
                           , spHash      :: FormHash
                           , spFixedSize :: FixedSize }

            | Synonym      { unSynonym    :: TSynonym
                           , spHash       :: FormHash
                           , spFixedSize  :: FixedSize }

            | Array        { unArray     :: TArray
                           , spHash      :: FormHash
                           , spRangeSize :: RangeSize }

            | Vector       { unVector    :: TVector
                           , spHash      :: FormHash
                           , spRangeSize :: RangeSize
                           , lenRepr     :: LengthRepr }

            | Record       { unRecord    :: TRecord
                           , spHash      :: FormHash
                           , spRangeSize :: RangeSize }

            | Combination  { unCombination :: TCombination
                           , spHash        :: FormHash
                           , spRangeSize   :: RangeSize
                           , flagsRepr     :: FlagsRepr }

           | Union         { unUnion    :: TUnion
                           , spHash      :: FormHash
                           , spRangeSize :: RangeSize
                           , tagRepr     :: TagRepr }
  deriving (Show, Ord, Eq, Data, Typeable)

instance Sized SpType where
  minSize (BuiltIn { spFixedSize = s}) = minSize s
  minSize (Synonym { spFixedSize = s}) = minSize s
  minSize (Array { spRangeSize = s}) = minSize s
  minSize (Vector { spRangeSize = s}) = minSize s
  minSize (Record { spRangeSize = s}) = minSize s
  minSize (Combination { spRangeSize = s}) = minSize s
  minSize (Union { spRangeSize = s}) = minSize s

  maxSize (BuiltIn { spFixedSize = s}) = maxSize s
  maxSize (Synonym { spFixedSize = s}) = maxSize s
  maxSize (Array { spRangeSize = s}) = maxSize s
  maxSize (Vector { spRangeSize = s}) = maxSize s
  maxSize (Record { spRangeSize = s}) = maxSize s
  maxSize (Combination { spRangeSize = s}) = maxSize s
  maxSize (Union { spRangeSize = s}) = maxSize s

typeName :: SpType -> Name
typeName (BuiltIn { unBuiltIn = (TBuiltIn b)}) = T.pack . show $ b
typeName (Synonym { unSynonym = (TSynonym n _)}) = n
typeName (Array { unArray = (TArray n _ _)}) = n
typeName (Vector { unVector = (TVector n _ _)}) = n
typeName (Record { unRecord = (TRecord n _)}) = n
typeName (Combination { unCombination = (TCombination n _)}) = n
typeName (Union { unUnion = (TUnion n _)}) = n

pruneBuiltIns :: [SpType] -> [SpType]
pruneBuiltIns fs = refBis ++ topLevel
  where
    (bis, topLevel) = L.partition isBuiltIn fs

    biNames = map (\(BuiltIn (TBuiltIn b) _ _) -> T.pack . show $ b) bis
    biMap = M.fromList $ zip biNames bis

    rsSet = S.fromList $ concatMap referencesOf topLevel
    biSet = S.fromList biNames

    refBiNames = S.toList $ rsSet `S.intersection` biSet
    refBis = map snd $ M.toList $ M.filterWithKey (\k _ -> k `elem` refBiNames) biMap

    isBuiltIn (BuiltIn {..}) = True
    isBuiltIn _ = False

-- TODO: Double-check the Schema hash can be recreated.
fromSchema :: SC.Schema -> Spec
fromSchema sc = Spec { specName = n
                     , specVersion = v
                     , specHash = overallHash
                     , specSize = size
                     , specDepth = maximumTypeDepth sc
                     , specTypeTagWidth = typeWidth
                     , specLengthTagWidth = lenWidth
                     , specTypes = fs'
                     }
  where
    n = SC.schemaName sc
    v = SC.schemaVersion sc
    fs' = topoSort $ pruneBuiltIns $ map snd $ M.toList specMap
    size = rangeFitting fs'

    (lenWidth, typeWidth) = tagWidths fs' (maxSize size)

    keepNames = S.fromList $ map typeName fs'

    tyMap = SC.schemaTypeMap sc
    thm = typeHashMap sc
    hashScType name = fromJust $ name `M.lookup` thm

    overallHash = let a = hashInit `hashUpdate` n `hashUpdate` v
                      sorted = sortBy (compare `on` fst) $ M.toList thm
                      filtered = filter (\(x,_) -> x `S.member` keepNames) sorted
                      hashStrs = map (hashToText . snd) filtered
                  in hashFinalize $ foldl hashUpdate a hashStrs

    specMap = fmap mkSpecType tyMap

    mkSpecType :: SC.ScType -> SpType
    mkSpecType p =
      case p of
        SC.BuiltIn t@(TBuiltIn b) ->
          let s = builtInSize b
          in BuiltIn t hash (FixedSize s)
        SC.Synonym  t@(TSynonym _ b) ->
          let s = builtInSize b
          in Synonym t hash (FixedSize s)
        SC.Array t@(TArray _ r i) ->
          let ref = lookupRef r
          in Array t hash (mkRangeSize (i * minSize ref) (i * maxSize ref))
        SC.Vector t@(TVector _ r i) ->
          let ref = lookupRef r
              repr = minimalExpression i
              repr' = LengthRepr repr
              reprSz = builtInSize repr
          in Vector t hash (mkRangeSize reprSz (reprSz + (i * maxSize ref))) repr'
        SC.Record t@(TRecord _ rs) ->
          let refs = lookupRefs rs
              sumMin = sumOfMinimums refs
              sumMax = sumOfMaximums refs
          in Record t hash (mkRangeSize sumMin sumMax)
        SC.Combination t@(TCombination _ rs) ->
          let refs = lookupRefs rs
              sumMax = sumOfMaximums refs
              repr = minimalBitField (fieldsLength rs)
              repr' = FlagsRepr repr
              reprSz = builtInSize repr
          in Combination t hash (mkRangeSize reprSz (reprSz + sumMax)) repr'
        SC.Union t@(TUnion _ rs) ->
          let refs = lookupRefs rs
              minMin = if anyEmpty rs
                          then 0
                          else minimumOfSizes refs
              maxMax = maximumOfSizes refs
              repr = minimalExpression (fieldsLength rs)
              repr' = TagRepr repr
              reprSz = builtInSize repr
          in Union t hash (mkRangeSize (reprSz + minMin) (reprSz + maxMax)) repr'
      where
        hash = hashScType (SC.typeName p)
        lookupRef r = fromJust $ r `M.lookup` specMap
        lookupField (Field _ r _) = Just $ lookupRef r
        lookupField (EmptyField _ _) = Nothing
        lookupRefs = mapMaybe lookupField . unFields

        anyEmpty (Fields fs) = any isEmpty fs

        isEmpty (EmptyField _ _) = True
        isEmpty _ = False


tagWidths :: Integral a => [SpType] -> a -> (LengthTagWidth, TypeTagWidth)
tagWidths types smax =
  (LengthTagWidth lengthTagWidth, TypeTagWidth typePrefixWidth)
  where
    typePrefixes = uniquePrefixes $ map (B.unpack . hashToByteString . spHash) types
    typePrefixWidth = case typePrefixes of
                        Just (p:_) -> fromIntegral $ length p
                        _ -> error "Need at least one prefix to determine a prefix length"
    lengthTagWidth = bytesRequired $ fromIntegral typePrefixWidth + fromIntegral smax

    uniquePrefixes :: Eq a => [[a]] -> Maybe [[a]]
    uniquePrefixes ls = let count = length ls
                        in case dropWhile (\l -> length l < count) $ map L.nub $ L.transpose $ map L.inits ls of
                              [] -> Nothing
                              l -> (Just . head) l

    bytesRequired :: Word64 -> Integer
    bytesRequired i | (0          <= i) && (i < 256) = 1
                    | (256        <= i) && (i < 65536) = 2
                    | (25536      <= i) && (i < 4294967296) = 4
                    | (4294967296 <= i) && (i <= 18446744073709551615) = 8
                    | otherwise = error $ "Cannot express value: " ++ show i

-- Topographically sort the types so that types with the fewest dependencies
-- show up first in the list of types. Types with the most dependencies are
-- ordered at the end. This allows languages that have order-dependencies to
-- rely on the sorted list for the order of code generation.
topoSort :: [SpType] -> [SpType]
topoSort sps = flattenSCCs . stronglyConnComp $ map m sps
  where
    m t = let n = typeName t
          in (t, n, referencesOf t)

-- | This is responsible for building a map from names to hashes out of a
-- Schema.  Hashes are of a textual that uniquely represents the type. The
-- representation chosen for is as follows:
--
--   1. For builtins, hash the string representation of the builtin.
--   2. For other types without fields:
--     a. State the type prototype
--     b. State the type name
--     c. State any other field data
--   3. For other types with fields:
--     a. State hte type prototype
--     b. State the type name
--     c. State a textual representation of each field
--
-- Field data that represents other types should be replaced by the hash of
-- that type. Field data that's represented as a built-in should use the name
-- of the built-in.
--
-- Fields are represented by the word "field" followed by the field name, the
-- hash of the referenced type, and a textual representation of the field's
-- index.
--
-- Empty Fields are represented by the word "field" followed by the field name
-- and a textual representation of the field's index.
--
-- An example:
--
--   This type: (const foo u8 12)
--
--   ... is represented as the hash of the string ...
--
--   "const foo u8 +12"
--
-- Another example:
--
--   This type: (array bar 64 baz)
--
--   ... is represented as the hash of the string ...
--
--   "array bar [hash of baz] +64"
--
typeHashMap :: SC.Schema -> M.Map Name FormHash
typeHashMap s = m
  where
    m = fmap typeHash (SC.schemaTypeMap s)
    lu n = hashToText (fromJust $ n `M.lookup` m)
    fieldStr (EmptyField n i) = ["field", n, showNumSigned i]
    fieldStr (Field n r i) = ["field", n, lu r, showNumSigned i]
    typeHash t =
      let str = case t of
                  SC.BuiltIn (TBuiltIn b) -> [T.pack . show $ b]
                  SC.Synonym (TSynonym n b) -> ["synonym", n, T.pack . show $ b]
                  SC.Array (TArray n r i) -> ["array", n, lu r, showNumSigned i]
                  SC.Vector (TVector n r i) -> ["vector", n, lu r, showNumSigned i]
                  SC.Record (TRecord n (Fields fs)) -> ["record", n] ++ concatMap fieldStr fs
                  SC.Combination (TCombination n (Fields fs)) -> ["combination", n] ++ concatMap fieldStr fs
                  SC.Union (TUnion n (Fields fs)) -> ["union", n] ++ concatMap fieldStr fs
      in hashText . T.unwords $ str

typeDepthMap :: SC.Schema -> M.Map Name Integer
typeDepthMap s = m
  where
    m = fmap typeDepth (SC.schemaTypeMap s)
    lu n = fromJust $ n `M.lookup` m

    fieldDepth (CT.Field { CT.fRef = r }) = lu r
    fieldDepth (CT.EmptyField {}) = 0

    maxFieldsDepth fs =
      let ds = map fieldDepth fs
      in maximum ds

    typeDepth :: SC.ScType -> Integer
    typeDepth t =
      case t of
        SC.BuiltIn (TBuiltIn {}) -> 1
        SC.Synonym (TSynonym {}) -> 2
        SC.Array (TArray _ r _) -> 1 + lu r
        SC.Vector (TVector _ r _) -> 1 + lu r
        SC.Record (TRecord _ (Fields fs)) -> 1 + maxFieldsDepth fs
        SC.Combination (TCombination _ (Fields fs)) -> 1 + maxFieldsDepth fs
        SC.Union (TUnion _ (Fields fs)) -> 1 + maxFieldsDepth fs

maximumTypeDepth :: SC.Schema -> Depth
maximumTypeDepth s = let m = typeDepthMap s
                     in Depth . maximum . M.elems $ m

showNumSigned :: (Ord a, Show a, Num a) => a -> T.Text
showNumSigned v = let v' = abs v
                      v'' = T.pack . show $ v'
                  in if v < 0
                       then '-' `T.cons` v''
                       else '+' `T.cons` v''

specTypeMap :: Spec -> M.Map Name SpType
specTypeMap s = let ts = specTypes s
                    ns = map typeName ts
                in M.fromList $ zip ns ts

specTypeTagMap :: Spec -> M.Map [Word8] SpType
specTypeTagMap s = let ts = specTypes s
                       tw = fromIntegral . unTypeTagWidth . specTypeTagWidth $ s
                       hs = map (take tw . hashToBytes . spHash) ts
                   in M.fromList $ zip hs ts

instance References SpType where
  referencesOf (BuiltIn {..}) = []
  referencesOf (Synonym s _ _) = referencesOf s
  referencesOf (Array f _ _) = referencesOf f
  referencesOf (Vector b _ _ r) = nub $ (T.pack . show) (unLengthRepr r) : referencesOf b
  referencesOf (Record s _ _) = referencesOf s
  referencesOf (Combination s _ _ r) = nub $ (T.pack . show) (unFlagsRepr r) : referencesOf s
  referencesOf (Union e _ _ r) = nub $ (T.pack . show) (unTagRepr r) : referencesOf e

prettyPrint :: Spec -> T.Text
prettyPrint = displayT . renderPretty 1 120 . pretty

pShow :: (Show a) => a -> Doc
pShow = text . T.pack . show

instance Pretty Spec where
  pretty (Spec n v h sz d tt lt fs) = parens (nest 2 (ps <$> pfs)) <+> line
    where
      ps = ("specification" <+> text n <+> text v) <$> details
      pfs = vcat $ map pretty fs
      details = vcat [pretty h, pretty sz <+> pretty d <+> pretty tt <+> pretty lt]

-- When printing spec types, the following is the general order of fields
--  (type name hash [references] [representations] [lengths])
instance Pretty SpType where
  pretty (BuiltIn (TBuiltIn b) h sz) = parens $ nest 2 (pt <$> pa)
    where
      pt = text "builtin" <+> pShow b
      pa = pretty h <$> pretty sz
  pretty (Synonym (TSynonym n b) h sz) = parens $ nest 2 (pt <$> pa)
    where
      pt = text "synonym" <+> text n
      pa = pretty h <$> pretty sz <$> pShow b
  pretty (Array (TArray n m i) h sz) = parens $ nest 2 (pt <$> pa)
    where
      pt = text "array" <+> text n
      pa = pretty h <$> pretty sz <$> (integer i <+> text m)
  pretty (Vector (TVector n m i) h sz bi) = parens $ nest 2 (pt <$> pa)
    where
      pt = text "vector" <+> text n
      pa = pretty h <$> pretty sz <$> pretty bi <$> (integer i <+> text m)
  pretty (Record (TRecord n rs) h sz) = prettyFieldedB0 "record" n rs sz h
  pretty (Combination (TCombination n rs) h sz bi) = prettyFieldedB1 "combination" n rs sz bi h
  pretty (Union (TUnion n rs) h sz bi) = prettyFieldedB1 "union" n rs sz bi h

-- Printing fielded-types involves hanging the name, the sizes, and the hash on
-- one line and the fields on following lines.
prettyFieldedB0 :: (Pretty sz) => T.Text -> T.Text -> Fields -> sz -> FormHash -> Doc
prettyFieldedB0 t n fs sz hash = parens $ nest 2 (pt <$> pfs)
  where
    pt = text t <+> text n
    pfs = pretty hash <$> pretty sz <$> specPrettyFields fs

prettyFieldedB1 :: (Pretty sz, Pretty bi) => T.Text -> T.Text -> Fields -> sz -> bi -> FormHash -> Doc
prettyFieldedB1 t n fs sz repr hash = parens $ nest 2 (pt <$> pfs)
  where
    pt = text t <+> text n
    pfs = pretty hash <$> pretty sz <$> pretty repr <$> specPrettyFields fs

specPrettyRefs :: Field -> Doc
specPrettyRefs (EmptyField n i) = parens $ text "field" <+> text n <+> integer i
specPrettyRefs (Field n m i) = parens $ text "field" <+> text n <+> text m <+> integer i

specPrettyFields :: Fields -> Doc
specPrettyFields (Fields fs) = parens $ nest 2 ("fields" <$> pfs)
  where
    pfs = vcat $ map specPrettyRefs fs
