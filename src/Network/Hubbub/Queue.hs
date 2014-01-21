module Network.Hubbub.Queue 
  ( LeaseSeconds (..)
  , SubscriptionEvent (..)
  , PublicationEvent (..)
  , emptySubscriptionQueue
  , emptyPublicationQueue
  , subscribe
  , publish
  , subscriptionLoop
  , publicationLoop
  ) where

import Network.Hubbub.SubscriptionDb
  ( Secret(..)
  , From(..)
  , Topic(..)
  , Callback(..)            
  )

import Prelude (Integer)
import Control.Monad ((>>=))
import Control.Concurrent.STM(STM,atomically)
import Control.Concurrent.STM.TQueue(TQueue,writeTQueue,readTQueue,newTQueue)
import Data.Eq (Eq)
import Data.Function ((.),($))
import Data.Maybe (Maybe)
import Text.Show (Show)
import System.IO (IO)

newtype LeaseSeconds = LeaseSeconds Integer deriving (Show,Eq)

data SubscriptionEvent =
  SubscribeEvent Topic Callback LeaseSeconds (Maybe Secret) (Maybe From)
  | UnsubscribeEvent Topic Callback
  deriving (Show,Eq)

data PublicationEvent = PublicationEvent Topic deriving (Eq,Show)

emptySubscriptionQueue :: STM (TQueue SubscriptionEvent)
emptySubscriptionQueue = newTQueue

subscribe :: TQueue SubscriptionEvent -> SubscriptionEvent -> STM ()
subscribe = writeTQueue 

emptyPublicationQueue :: STM (TQueue PublicationEvent)
emptyPublicationQueue = newTQueue

publish :: TQueue PublicationEvent -> PublicationEvent -> STM ()
publish = writeTQueue

nextSubscriptionEvent :: TQueue SubscriptionEvent -> STM SubscriptionEvent
nextSubscriptionEvent = readTQueue

nextPublicationEvent :: TQueue PublicationEvent -> STM PublicationEvent
nextPublicationEvent = readTQueue

queueLoop :: (TQueue a -> STM a) -> (a -> IO ()) -> TQueue a -> IO ()
queueLoop pop f q = loop
  where
    loop = do
      (atomically . pop $ q) >>= f
      loop

subscriptionLoop :: (SubscriptionEvent -> IO ()) -> TQueue SubscriptionEvent -> IO ()
subscriptionLoop = queueLoop nextSubscriptionEvent

publicationLoop :: (PublicationEvent -> IO ()) -> TQueue PublicationEvent -> IO ()
publicationLoop = queueLoop nextPublicationEvent
