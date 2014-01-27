{-# LANGUAGE TemplateHaskell #-}
module Main where

import Prelude (Int)

import Control.Applicative ((<$>))
import Control.Exception (handle)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TVar (TVar,newTVar,readTVar,modifyTVar)
import Control.Monad (return,forM_)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (encode,decode)
import Data.Aeson.TH (deriveJSON,defaultOptions)
import Data.Eq (Eq)
import Data.Function (($),(.),const)
import Data.Functor (fmap)
import Data.List ((++))
import Data.Map (Map,insert,delete,lookup,empty,elems)
import Data.Maybe (Maybe(Just,Nothing),fromMaybe)
import Data.Text (Text)
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import Network.HTTP.Conduit
  ( parseUrl
  , withManager
  , http
  , urlEncodedBody
  , simpleHttp )
import Network.Wai (Application)
import Network.Wai.Middleware.Static (staticPolicy,noDots,(>->),addBase)
import qualified Network.Wai.Handler.Warp as Warp
import qualified Network.Wai.Handler.WebSockets as WaiWS
import qualified Network.WebSockets as WS
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import System.IO (IO,putStrLn)
import Text.Show (Show,show)
import Web.Scotty (scottyApp,get,post,jsonData,middleware,param,file,text)

port :: Int
port = 5002

data Post = Post { subject::Text , body::Text } deriving (Show,Eq)
$(deriveJSON defaultOptions ''Post)

type ServerState = Map UUID WS.Connection

main :: IO ()
main = do
  state <- atomically $ newTVar empty
  liftIO subscribe
  app <- scottyApp $ do
    middleware logStdoutDev
    middleware $ staticPolicy (noDots >-> addBase "www/static")
    get "/" $ file "www/subscriber/show.html"
    get "/callback" $ do
      chal <- param "hub.challenge"
      text chal
    post "/callback" $ do
      ps <- jsonData
      liftIO $ distribute state ps 
      
  warpServer state app

warpServer :: TVar ServerState -> Application -> IO ()
warpServer state = Warp.runSettings Warp.defaultSettings {
    Warp.settingsPort = port ,
    Warp.settingsIntercept = WaiWS.intercept (socketApp state)
  } 

socketApp :: TVar ServerState -> WS.ServerApp
socketApp state pending = do
  conn <- WS.acceptRequest pending
  uuid <- nextRandom
  liftIO $ atomically $ modifyTVar state (insert uuid conn)
  putStrLn $ "websocket connected with uuid: " ++ show uuid
  posts <- getPosts
  distributeToConn posts conn
  subscribe
  clientLoop state uuid

clientLoop :: TVar ServerState -> UUID -> IO ()
clientLoop state uuid = do
  conn <- lookup uuid <$> atomically (readTVar state)
  case conn of
    Nothing -> return ()
    Just c  -> handle disconnect (const () <$> WS.receiveDataMessage c)

  where
    disconnect (WS.ConnectionClosed) = 
      liftIO $ atomically $ modifyTVar state (delete uuid)

getPosts :: IO [Post]
getPosts = fromMaybe [] . decode <$> simpleHttp "http://localhost:5001/json"

    
subscribe :: IO ()
subscribe = do
  request <- parseUrl "http://localhost:5000/subscriptions" 
  withManager $ \manager -> do
    _ <- http (postRequest request) manager
    return ()

  where
    postRequest = urlEncodedBody [
      ("hub.mode","subscribe")
      , ("hub.topic","http://localhost:5001/json")
      , ("hub.callback","http://localhost:5002/callback")
      , ("hub.secret","supersecretsquirrel")]

distribute :: TVar ServerState -> [Post] -> IO ()
distribute state posts = do
  connections <- fmap elems . liftIO . atomically . readTVar $ state
  forM_ connections (distributeToConn posts)

distributeToConn :: [Post] -> WS.Connection -> IO ()
distributeToConn posts conn = WS.sendTextData conn (encode posts)
    
