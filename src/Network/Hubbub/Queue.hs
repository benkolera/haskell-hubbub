module Network.Hubbub.Queue 
  ( LeaseSeconds (..)
  , Mode (..)
  , SubscriptionEvent (..)
  , subscribe
  , publish
  , subscriptionLoop
  , publishLoop
  ) where

import Network.Hubbub.SubscriptionDb
  ( Secret(..)
  , From(..)
  , Topic(..)
  , Callback(..)            
  )
  
import Control.Concurrent.STM(STM,atomically)
import Control.Concurrent.STM.TQueue(TQueue,writeTQueue,readTQueue)

newtype LeaseSeconds = LeaseSeconds Integer deriving (Show)

data Mode =
  SubscribeMode
  | UnsubscribeMode
  deriving (Show)

data SubscriptionEvent =
  SubscriptionEvent
  Topic
  Callback
  Mode
  (Maybe LeaseSeconds)
  (Maybe Secret)
  (Maybe From)
  deriving (Show)

subscribe :: TQueue SubscriptionEvent -> SubscriptionEvent -> STM ()
subscribe = writeTQueue 

publish :: TQueue Topic -> Topic -> STM ()
publish = writeTQueue

nextSubscriptionEvent :: TQueue SubscriptionEvent -> STM SubscriptionEvent
nextSubscriptionEvent = readTQueue

nextPublishEvent :: TQueue Topic -> STM Topic
nextPublishEvent = readTQueue

queueLoop :: (TQueue a -> STM a) -> (a -> IO ()) -> TQueue a -> IO ()
queueLoop pop f q = loop
  where
    loop = do
      (atomically . pop $ q) >>= f
      loop

subscriptionLoop :: (SubscriptionEvent -> IO ()) -> TQueue SubscriptionEvent -> IO ()
subscriptionLoop = queueLoop nextSubscriptionEvent

publishLoop :: (Topic -> IO ()) -> TQueue Topic -> IO ()
publishLoop = queueLoop nextPublishEvent
