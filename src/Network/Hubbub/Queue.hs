module Network.Hubbub.Queue 
  ( AttemptCount (AttemptCount)
  , ContentType (ContentType)
  , DistributionEvent (DistributionEvent)
  , LeaseSeconds (LeaseSeconds)
  , ResourceBody (ResourceBody)
  , SubscriptionEvent (Subscribe,Unsubscribe)
  , PublicationEvent (PublicationEvent)
  , distribute
  , distributionAttemptCount
  , distributionBody
  , distributionCallback
  , distributionContentType
  , distributionLoop
  , distributionSecret
  , distributionTopic
  , emptyDistributionQueue
  , emptyPublicationQueue
  , emptySubscriptionQueue
  , fromAttemptCount
  , fromContentType
  , fromLeaseSeconds
  , fromResourceBody
  , publicationLoop
  , publish
  , publicationAttemptCount
  , publicationTopic
  , subscribe
  , subscribeAttemptCount 
  , subscribeCallback
  , subscribeFrom    
  , subscribeLeaseSeconds
  , subscribeSecret
  , subscribeTopic
  , subscriptionLoop
  , unsubscribeAttemptCount
  , unsubscribeCallback
  , unsubscribeTopic
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
import qualified Data.ByteString      as Bs
import qualified Data.ByteString.Lazy as BsL 
import Data.Eq (Eq)
import Data.Function ((.),($))
import Data.Maybe (Maybe)
import Text.Show (Show)
import System.IO (IO)

newtype LeaseSeconds = LeaseSeconds Integer deriving (Show,Eq)
fromLeaseSeconds :: LeaseSeconds -> Integer
fromLeaseSeconds (LeaseSeconds ls) = ls
  
newtype AttemptCount = AttemptCount Integer deriving (Show,Eq)
fromAttemptCount :: AttemptCount -> Integer
fromAttemptCount (AttemptCount at) = at

newtype ResourceBody = ResourceBody BsL.ByteString deriving (Show,Eq)
fromResourceBody :: ResourceBody -> BsL.ByteString
fromResourceBody (ResourceBody rb) = rb

newtype ContentType  = ContentType Bs.ByteString deriving (Show,Eq)
fromContentType :: ContentType -> Bs.ByteString
fromContentType (ContentType ct) = ct

data SubscriptionEvent =
  Subscribe {
    subscribeTopic:: Topic
    , subscribeCallback::Callback
    , subscribeLeaseSeconds::LeaseSeconds
    , subscribeAttemptCount::AttemptCount
    , subscribeSecret:: Maybe Secret
    , subscribeFrom :: Maybe From
    }
  | Unsubscribe {
    unsubscribeTopic::Topic
    , unsubscribeCallback::Callback
    , unsubscribeAttemptCount::AttemptCount
    }
  deriving (Show,Eq)

data PublicationEvent = PublicationEvent {
  publicationTopic::Topic
  , publicationAttemptCount::AttemptCount
  } deriving (Eq,Show)

data DistributionEvent = DistributionEvent {
  distributionTopic::Topic                    
  , distributionCallback::Callback                 
  , distributionContentType::Maybe ContentType
  , distributionBody::ResourceBody             
  , distributionSecret::Maybe Secret
  , distributionAttemptCount::AttemptCount
  } deriving (Eq,Show)

emptySubscriptionQueue :: STM (TQueue SubscriptionEvent)
emptySubscriptionQueue = newTQueue

subscribe :: TQueue SubscriptionEvent -> SubscriptionEvent -> STM ()
subscribe = writeTQueue 

emptyPublicationQueue :: STM (TQueue PublicationEvent)
emptyPublicationQueue = newTQueue

publish :: TQueue PublicationEvent -> PublicationEvent -> STM ()
publish = writeTQueue

emptyDistributionQueue :: STM (TQueue DistributionEvent)
emptyDistributionQueue = newTQueue

distribute :: TQueue DistributionEvent -> DistributionEvent -> STM ()
distribute = writeTQueue

nextSubscriptionEvent :: TQueue SubscriptionEvent -> STM SubscriptionEvent
nextSubscriptionEvent = readTQueue

nextPublicationEvent :: TQueue PublicationEvent -> STM PublicationEvent
nextPublicationEvent = readTQueue

nextDistributionEvent :: TQueue DistributionEvent -> STM DistributionEvent
nextDistributionEvent = readTQueue

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

distributionLoop :: (DistributionEvent -> IO ()) -> TQueue DistributionEvent -> IO ()
distributionLoop = queueLoop nextDistributionEvent
