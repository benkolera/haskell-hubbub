module Network.Hubbub.Test (hubbubSuite) where

import Network.Hubbub ()

import Test.Tasty (TestTree,testGroup)

hubbubSuite :: TestTree
hubbubSuite = testGroup "Hubbub" []
 
