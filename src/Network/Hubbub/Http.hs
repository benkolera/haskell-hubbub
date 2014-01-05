{-#  LANGUAGE OverloadedStrings #-}

module Network.Hubbub.Http where

import Network.HTTP.Conduit

import Data.Conduit
import Data.Conduit.Binary (sinkFile)

import Control.Monad.IO.Class (liftIO)

main :: IO ()
main = runResourceT $ do
  manager <- liftIO $ newManager conduitManagerSettings
  req <- liftIO $ parseUrl "http://www.example.com/foo.txt"
  res <- http req manager
  responseBody res $$+- sinkFile "foo.txt"
