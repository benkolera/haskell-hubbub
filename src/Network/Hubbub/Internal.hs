module Network.Hubbub.Internal
  ( DoDistributionEventError(DoDistHttpError)
  , DoPublicationEventError(DoPubHttpError,DoPubApiError)
  , DoSubscriptionEventError(DoSubHttpError,DoSubApiError)    
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
  , fromLeaseSeconds
  , publicationTopic )
  
import Network.Hubbub.SubscriptionDb
  ( Subscription (Subscription)
  , SubscriptionDbApi
  , addSubscription
  , removeSubscription
  , getTopicSubscriptions
  )

import Prelude (undefined)
import Control.Exception.Base (SomeException)
import Control.Error (EitherT,fmapLT)
import Control.Monad (unless,return)
import Control.Monad.IO.Class (liftIO)
import Data.Bool (not)
import Data.Function (($))
import Data.List (map)
import Data.Time(getCurrentTime)
import Data.DateTime (addSeconds)
import System.IO (IO)
import System.Random (RandomGen)
import Text.Show (Show)

--------------------------------------------------------------------------------
-- doSubscriptionEvent
--------------------------------------------------------------------------------

data DoSubscriptionEventError =
  DoSubHttpError HttpError
  | DoSubApiError SomeException
  deriving (Show)

doSubscriptionEvent :: RandomGen r =>
  r ->
  SubscriptionDbApi ->
  SubscriptionEvent ->
  EitherT DoSubscriptionEventError IO ()

-- For a subscribe event
doSubscriptionEvent rng api ev@(Subscribe t cb ls _ s f) = do
  time <- liftIO getCurrentTime
  ok   <- fmapLT DoSubHttpError $ verifySubscriptionEvent rng ev
  unless (not ok) $ fmapLT DoSubApiError $ addSubscription api t cb (sub time)
  where
    sub tm = Subscription tm (exp tm) s f
    exp = addSeconds (fromLeaseSeconds ls)

-- For an Unsubscribe event
doSubscriptionEvent rng api ev@(Unsubscribe t cb _) = do
  ok   <- fmapLT DoSubHttpError $ verifySubscriptionEvent rng ev
  unless (not ok) $ fmapLT DoSubApiError $ removeSubscription api t cb

--------------------------------------------------------------------------------
-- doPublicationEvent
--------------------------------------------------------------------------------  

data DoPublicationEventError =
  DoPubHttpError HttpError
  | DoPubApiError SomeException
  deriving (Show)

doPublicationEvent ::
  SubscriptionDbApi ->
  PublicationEvent ->
  EitherT DoPublicationEventError IO [DistributionEvent]
doPublicationEvent api ev = do
  subs    <- fmapLT DoPubApiError $ getTopicSubscriptions api topic 
  (ct,bd) <- fmapLT DoPubHttpError $ getPublishedResource ev
  return $ map (makeDistEvent ct bd) subs
  where
    topic   = publicationTopic ev
    makeDistEvent ct bd (cb ,Subscription _ _ sec _) =
      DistributionEvent
      topic
      cb
      ct
      bd
      sec
      (AttemptCount 1)

--------------------------------------------------------------------------------
-- doDistributionEvent 
--------------------------------------------------------------------------------

data DoDistributionEventError = DoDistHttpError HttpError deriving (Show)

doDistributionEvent :: 
  ServerUrl ->
  DistributionEvent ->  
  EitherT DoDistributionEventError IO ()
doDistributionEvent su ev = fmapLT DoDistHttpError $ distributeResource ev su

