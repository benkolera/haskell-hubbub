module Network.Hubbub.Queue 
  ( AttemptCount (AttemptCount)
  , ContentType (ContentType)
  , DistributionEvent (DistributionEvent)
  , LeaseSeconds (LeaseSeconds)
  , ResourceBody (ResourceBody)
  , Retryable
  , RetryDelay (RetryDelayMillis)
  , SubscriptionEvent (Subscribe,Unsubscribe)
  , PublicationEvent (PublicationEvent)
  , attempts
  , incrementAttempts
  , retryDelay
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
  , queueLoop
  , retryDelaySeconds
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

import Prelude (Float,Integer,(/),(-),(+),(*),fromIntegral)
import Control.Error (EitherT,runEitherT)
import Control.Monad (return)
import Control.Concurrent (threadDelay,forkIO)
import Control.Concurrent.STM(STM,atomically)
import Control.Concurrent.STM.TQueue(TQueue,writeTQueue,readTQueue,newTQueue)
import qualified Data.ByteString      as Bs
import qualified Data.ByteString.Lazy as BsL
import Data.Either (Either(Left,Right))
import Data.Eq (Eq)
import Data.Function ((.),($),const)
import Data.Functor (fmap)
import Data.Maybe (Maybe,maybe)
import Safe (atMay)
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

newtype RetryDelay = RetryDelayMillis Integer deriving (Show,Eq)
retryDelayPicos :: RetryDelay -> Integer
retryDelayPicos (RetryDelayMillis ms) = ms * 1000
retryDelaySeconds :: RetryDelay -> Float
retryDelaySeconds (RetryDelayMillis ms) = fromIntegral ms / 1000

class Retryable a where
  attempts :: a -> Integer
  incrementAttempts :: a -> a

  retryDelay :: a -> Maybe RetryDelay
  retryDelay =
    fmap RetryDelayMillis .
    atMay retrySchedule .
    fromIntegral .
    (+ (-1)) .
    attempts
    where 
      retrySchedule = [100,500,1000,5000,10000]



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

instance Retryable SubscriptionEvent where
  attempts ev@(Subscribe {}) = fromAttemptCount . subscribeAttemptCount $ ev
  attempts ev@(Unsubscribe {}) = fromAttemptCount . unsubscribeAttemptCount $ ev
  incrementAttempts ev@(Subscribe { subscribeAttemptCount = c }) =
    ev { subscribeAttemptCount = AttemptCount . (+1) . fromAttemptCount $ c }
  incrementAttempts ev@(Unsubscribe { unsubscribeAttemptCount = c }) =
    ev { unsubscribeAttemptCount = AttemptCount . (+1) . fromAttemptCount $ c }
  
data PublicationEvent = PublicationEvent {
  publicationTopic::Topic
  , publicationAttemptCount::AttemptCount
  } deriving (Eq,Show)

instance Retryable PublicationEvent where
  attempts (PublicationEvent _ (AttemptCount c)) = c
  incrementAttempts (PublicationEvent t (AttemptCount c)) =
    PublicationEvent t (AttemptCount $ c + 1)

data DistributionEvent = DistributionEvent {
  distributionTopic::Topic                    
  , distributionCallback::Callback                 
  , distributionContentType::Maybe ContentType
  , distributionBody::ResourceBody             
  , distributionSecret::Maybe Secret
  , distributionAttemptCount::AttemptCount
  } deriving (Eq,Show)

instance Retryable DistributionEvent where
  attempts DistributionEvent { distributionAttemptCount = AttemptCount c } = c
  incrementAttempts ev@DistributionEvent{}  =
    ev { distributionAttemptCount = AttemptCount . (+1) . attempts $ ev }

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

queueLoop :: Retryable a =>
  (a -> EitherT e IO ()) ->
  (a -> e -> Maybe RetryDelay -> IO ()) ->
  TQueue a ->
  IO ()
queueLoop doEvent logErr q = loop
  where
    loop = do
      ev  <- atomically . readTQueue $ q
      res <- runEitherT $ doEvent ev
      case res of
        (Right _) -> return ()
        (Left e)  ->
          let newEv = incrementAttempts ev
              retry = retryDelay newEv
          in do
            maybe (return ()) (requeue newEv) retry 
            logErr newEv e retry 
      loop
    requeue ev delay = fmap (const ()) . forkIO $ do
      threadDelay . fromIntegral . retryDelayPicos $ delay
      atomically (writeTQueue q ev)

subscriptionLoop ::
  (SubscriptionEvent -> EitherT e IO ()) ->
  (SubscriptionEvent -> e -> Maybe RetryDelay -> IO ()) ->
  TQueue SubscriptionEvent ->
  IO ()
subscriptionLoop = queueLoop

publicationLoop ::
  (PublicationEvent -> EitherT e IO ()) ->
  (PublicationEvent -> e -> Maybe RetryDelay -> IO ()) ->
  TQueue PublicationEvent ->
  IO ()
publicationLoop = queueLoop

distributionLoop ::
  (DistributionEvent -> EitherT e IO ()) ->
  (DistributionEvent -> e -> Maybe RetryDelay -> IO ()) ->  
  TQueue DistributionEvent ->
  IO ()
distributionLoop = queueLoop
