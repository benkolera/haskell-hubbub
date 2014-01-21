module Network.Hubbub.Queue 
  ( LeaseSeconds (..)
  , Mode (..)
  , SubscriptionEvent (..)
  , PublicationEvent (..)
  , emptySubscriptionQueue
  , emptyPublicationQueue
  , modeFromText
  , modeToText
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
import Data.Maybe (Maybe(Just,Nothing))
import Data.Text (Text)
import Text.Show (Show)
import System.IO (IO)

newtype LeaseSeconds = LeaseSeconds Integer deriving (Show,Eq)

data Mode =
  SubscribeMode
  | UnsubscribeMode
  deriving (Eq,Show)

modeToText :: Mode -> Text
modeToText SubscribeMode   = "subscribe"
modeToText UnsubscribeMode = "unsubscribe"

modeFromText :: Text -> Maybe Mode
modeFromText "subscribe"   = Just SubscribeMode
modeFromText "unsubscribe" = Just SubscribeMode
modeFromText _             = Nothing

data SubscriptionEvent =
  SubscriptionEvent
  Topic
  Callback
  Mode
  (Maybe LeaseSeconds)
  (Maybe Secret)
  (Maybe From)
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
