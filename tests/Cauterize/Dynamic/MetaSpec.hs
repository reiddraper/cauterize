module Cauterize.Dynamic.MetaSpec
  ( spec
  ) where

import Cauterize.Dynamic.Meta

import Test.Hspec
import TestSupport

import Control.Monad
import qualified Data.ByteString as B
import qualified Data.Text.Lazy as T

spec :: Spec
spec =
  describe "dynamic transcoding against test_schema.txt" $
    itWithSpec "random transcodes are equal" $ \specification -> replicateM_ 10000 $ do
      t <- dynamicMetaGen specification
      let p = dynamicMetaPack specification t
      let u = dynamicMetaUnpack specification p
      case u of
        Left e -> expectationFailure $ "could not unpack dynamically generated type: '" ++ T.unpack e ++ "'. Type was: " ++ show t ++ ". Bytes were: " ++ show (B.unpack p) ++ "."
        Right (t', b) -> if t' /= t
                          then expectationFailure $ "unpacking packed type did not yield equal value: " ++ show t ++ " /= " ++ show t'
                          else 0 `shouldBe` B.length b -- should not be any remaining data
