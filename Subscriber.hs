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
import Data.ByteString (ByteString)
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

--------------------------------------------------------------------------------
-- Data type (Same as publisher) -----------------------------------------------
--------------------------------------------------------------------------------

data Post = Post { subject::Text , body::Text } deriving (Show,Eq)
$(deriveJSON defaultOptions ''Post)

--------------------------------------------------------------------------------
-- Scotty App ------------------------------------------------------------------
--------------------------------------------------------------------------------

port :: Int
port = 5002

-- We need to keep track of all of the Websocket connections that we have open.
type ServerState = Map UUID WS.Connection

main :: IO ()
main = do
  -- Initalise a new TVar (ServerState) to be empty
  state <- atomically $ newTVar empty

  app <- scottyApp $ do
    middleware logStdoutDev
    middleware $ staticPolicy (noDots >-> addBase "www/static")

    -- Show the web page to the browser. No need for blaze here.
    get "/" $ file "www/subscriber/show.html"

    -- The hub verifies subscriptions with us. We need to respond back with the
    -- challenge to accept it.
    get "/callback" $ do
      chal <- param "hub.challenge"
      text chal

    -- This is what gets called when the hub publishes to us  
    post "/callback" $ do
      ps <- jsonData
      liftIO $ distribute state ps 

  -- We need to start warp ourselves here because of the extra websocket stuff
  -- that we are doing.    
  warpServer state app

--------------------------------------------------------------------------------
-- Handle websockets through the wai interceptor -------------------------------
--------------------------------------------------------------------------------

warpServer :: TVar ServerState -> Application -> IO ()
warpServer state = Warp.runSettings Warp.defaultSettings {
    Warp.settingsPort = port ,
    Warp.settingsIntercept = WaiWS.intercept (handleNewConnection state)
  } 

-- This is called every time there is a new websocket connection.
-- We need to return an IO action that will initialize what we need
-- and handle all socket comms until the socket is closed.
handleNewConnection :: TVar ServerState -> WS.ServerApp
handleNewConnection state pending = do
  conn <- WS.acceptRequest pending

  -- Generate a UUID for the connection and save it into our TVar
  uuid <- nextRandom
  liftIO $ atomically $ modifyTVar state (insert uuid conn)
  putStrLn $ "websocket connected with uuid: " ++ show uuid

  -- Grab the current posts and push them to the browser.
  posts <- getPosts
  distributeToConn posts conn

  -- Make sure subscription is current.
  subscribe

  -- And then return the program that will handle all comms.
  clientLoop state uuid

clientLoop :: TVar ServerState -> UUID -> IO ()
clientLoop state uuid = do
  -- Lets grab our connection.
  conn <- lookup uuid <$> atomically (readTVar state)
  case conn of
    Nothing -> return () -- Exit if there is no connection.
    Just c  -> do
      -- Get a message from the connection (handles pings,pongs & disconnects)
      -- Catch disconnect and delete the connection from state.
      _ <- handle disconnect (const () <$> (WS.receiveData c :: IO ByteString))
      clientLoop state uuid

  where
    disconnect (WS.ConnectionClosed) = 
      liftIO $ atomically $ modifyTVar state (delete uuid)

distribute :: TVar ServerState -> [Post] -> IO ()
distribute state posts = do
  connections <- fmap elems . atomically . readTVar $ state
  forM_ connections (distributeToConn posts)

distributeToConn :: [Post] -> WS.Connection -> IO ()
distributeToConn posts conn = WS.sendTextData conn (encode posts)

--------------------------------------------------------------------------------
-- HTTP back and forth to the hub ----------------------------------------------
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
