module Network.Hubbub.Internal
  ( DoDistributionEventError(DoDistHttpError)
  , DoPublicationEventError(DoPubHttpError,DoPubAcidError)
  , DoSubscriptionEventError(DoSubHttpError,DoSubAcidError)    
  , doDistributionEvent
  , doPublicationEvent
  , doSubscriptionEvent ) where

import Network.Hubbub.Http
  ( HttpError
  , ServerUrl
  , getPublishedResource
  , distributeResource
  , verifySubscriptionEvent
  )
  
import Network.Hubbub.Queue
  ( AttemptCount(AttemptCount)
  , DistributionEvent(DistributionEvent)
  , PublicationEvent

  , SubscriptionEvent (Subscribe,Unsubscribe)
  , LeaseSeconds (LeaseSeconds)
  , publicationTopic )
import Network.Hubbub.SubscriptionDb
  ( AddSubscription (AddSubscription)
  , GetTopicSubscriptions(GetTopicSubscriptions)
  , RemoveSubscription (RemoveSubscription)
  , Subscription (Subscription)
  , SubscriptionDb
  )

import Prelude (undefined)
import Control.Exception.Base (IOException)
import Control.Error (EitherT,tryIO,fmapLT,bimapEitherT)
import Control.Monad (unless,return)
import Control.Monad.IO.Class (liftIO)
import Data.Acid(AcidState,query,update)
import Data.Bool (not)
import Data.Function (($),(.))
import Data.List (map)
import Data.Map (assocs)
import Data.Time(getCurrentTime)
import Data.DateTime (addSeconds)
import System.IO (IO)
import System.Random (RandomGen)
import Text.Show (Show)

data DoSubscriptionEventError =
  DoSubHttpError HttpError
  | DoSubAcidError IOException
  deriving (Show)

doSubscriptionEvent :: RandomGen r =>
  r ->
  AcidState SubscriptionDb ->
  SubscriptionEvent ->
  EitherT DoSubscriptionEventError IO ()
doSubscriptionEvent rng acid ev@(Subscribe t cb ls _ s f) = do
  time <- liftIO getCurrentTime
  ok   <- fmapLT DoSubHttpError $ verifySubscriptionEvent rng ev
  unless (not ok) $ fmapLT DoSubAcidError . tryIO $ doAcidUpdate time
  where
    doAcidUpdate tm = update acid (AddSubscription t cb $ createDbSub tm ls s f)
    createDbSub tm (LeaseSeconds lsecs) = Subscription tm (addSeconds lsecs tm)

doSubscriptionEvent rng acid ev@(Unsubscribe t cb _) = do
  ok   <- fmapLT DoSubHttpError $ verifySubscriptionEvent rng ev
  unless (not ok) $ (fmapLT DoSubAcidError) . tryIO . update acid $ oper
  where
    oper = RemoveSubscription t cb

data DoPublicationEventError =
  DoPubHttpError HttpError
  | DoPubAcidError IOException
  deriving (Show)

doPublicationEvent :: 
  AcidState SubscriptionDb ->
  PublicationEvent ->
  EitherT DoPublicationEventError IO [DistributionEvent]
doPublicationEvent acid ev = do
  subs    <- (bimapEitherT DoPubAcidError assocs) . tryIO . query acid $ getSubs
  (ct,bd) <- fmapLT DoPubHttpError $ getPublishedResource ev
  return $ map (makeDistEvent ct bd) subs
  where
    topic   = publicationTopic ev
    getSubs = GetTopicSubscriptions topic
    makeDistEvent ct bd (cb ,Subscription _ _ sec _) =
      DistributionEvent
      topic
      cb
      ct
      bd
      sec
      (AttemptCount 1)

data DoDistributionEventError = DoDistHttpError HttpError deriving (Show)

doDistributionEvent :: 
  ServerUrl ->
  DistributionEvent ->  
  EitherT DoDistributionEventError IO ()
doDistributionEvent su ev = fmapLT DoDistHttpError $ distributeResource ev su

