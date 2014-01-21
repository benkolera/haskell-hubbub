module Network.Hubbub () where

import Network.Hubbub.Internal (doSubscriptionEvent)
import Network.Hubbub.SubscriptionDb
  (SubscriptionDb (..)
  , Subscription (..)
  , Topic (..)
  , Secret(..)
  , From(..)
  , Callback(..)
  , AddSubscription (..)
  )

import Network.Hubbub.Queue 
  (SubscriptionEvent (..)
  , Mode (..)
  , LeaseSeconds (..)
  , subscriptionLoop
  , publishLoop
  , subscribe
  , publish
  )

import Control.Concurrent.STM.TQueue(TQueue)

import Data.Acid(update,AcidState)
import Data.Time(getCurrentTime)
import Data.DateTime (addSeconds)

subscriptionThread :: AcidState SubscriptionDb -> TQueue SubscriptionEvent -> IO ()
subscriptionThread acid = subscriptionLoop (doSubscriptionEvent acid)

publishThread :: TQueue Topic -> IO ()
publishThread = publishLoop doPublish
  where
    doPublish = undefined    
