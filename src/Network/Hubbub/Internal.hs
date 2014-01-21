module Network.Hubbub.Internal (doSubscriptionEvent) where

import Network.Hubbub.Http (HttpError,verifySubscriptionEvent)
import Network.Hubbub.Queue
  ( SubscriptionEvent (SubscribeEvent,UnsubscribeEvent)
  , LeaseSeconds (LeaseSeconds) )
import Network.Hubbub.SubscriptionDb
  ( AddSubscription (AddSubscription)
  , RemoveSubscription (RemoveSubscription)
  , Subscription (Subscription)
  , SubscriptionDb )

import Prelude (undefined)
import Control.Exception.Base (IOException)
import Control.Error (EitherT,tryIO,fmapLT)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.Acid(update,AcidState)
import Data.Bool (not)
import Data.Function (($),(.))
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
doSubscriptionEvent rng acid ev@(SubscribeEvent t cb ls s f) = do
  time <- liftIO getCurrentTime
  ok   <- fmapLT DoSubHttpError $ verifySubscriptionEvent rng ev
  unless (not ok) $ fmapLT DoSubAcidError . tryIO $ doAcidUpdate time
  where
    doAcidUpdate tm = update acid (AddSubscription t cb $ createDbSub tm ls s f)
    createDbSub tm (LeaseSeconds lsecs) = Subscription tm (addSeconds lsecs tm)

doSubscriptionEvent rng acid ev@(UnsubscribeEvent t cb) = do
  ok   <- fmapLT DoSubHttpError $ verifySubscriptionEvent rng ev
  unless (not ok) $ fmapLT DoSubAcidError $ tryIO doAcidUpdate
  where
    doAcidUpdate = update acid (RemoveSubscription t cb)

