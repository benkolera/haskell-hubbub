module Network.Hubbub 
  ( Topic(Topic)
  , Callback(..)
  , LeaseSeconds(..)
  , Secret(..)
  , From(..)
  , Mode(..)
  , SubscriptionEvent(..)
  , subscribe
  , publish
  ) where

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
subscriptionThread acid = subscriptionLoop doSubscribe
  where
    doSubscribe (SubscriptionEvent t cb m ls s f) = 
      do time <- getCurrentTime
         ok   <- checkSubscriber t cb m ls
         _    <- update acid (AddSubscription t cb $ createDbSub time ls s f)
         return ()
    checkSubscriber t cb m ls = return True
    createDbSub t ls s f = Subscription t (expiry t ls) s f
    expiry time ls = fmap (\ (LeaseSeconds s) -> addSeconds s time) ls 


publishThread :: TQueue Topic -> IO ()
publishThread = publishLoop doPublish
  where
    doPublish = undefined    
