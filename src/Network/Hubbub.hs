module Network.Hubbub 
  ( Callback(Callback)
  , HttpResource(HttpResource)
  , HubbubConfig(HubbubConfig)
  , HubbubAcidConfig(HubbubAcidConfig)
  , HubbubEnv
  , LeaseSeconds(LeaseSeconds)
  , Secret(Secret)
  , ServerUrl(ServerUrl)
  , Topic(Topic)
  , initializeHubbubAcid
  , publish
  , shutdownHubbub
  , subscribe
  , unsubscribe
  ) where

import Network.Hubbub.Internal
  ( doDistributionEvent
  , doSubscriptionEvent
  , doPublicationEvent )
import Network.Hubbub.Http (ServerUrl(ServerUrl))
import Network.Hubbub.Queue
  ( AttemptCount(AttemptCount)
  , DistributionEvent
  , LeaseSeconds(LeaseSeconds)    
  , PublicationEvent(PublicationEvent)
  , RetryDelay
  , SubscriptionEvent(Subscribe,Unsubscribe)
  , emptyDistributionQueue
  , emptyPublicationQueue
  , emptySubscriptionQueue
  , distributionLoop
  , publicationLoop
  , retryDelaySeconds
  , subscriptionLoop )

import qualified Network.Hubbub.Queue as Q 
import Network.Hubbub.SubscriptionDb
  ( Callback(Callback)
  , From(From)
  , HttpResource(HttpResource)
  , Secret(Secret)
  , SubscriptionDbApi
  , Topic(Topic)
  , shutdownDb )
import Network.Hubbub.SubscriptionDb.Acid (acidDbApi,emptyDb)

import Prelude (Int)
import Control.Applicative ((<$>),(<*>))
import Control.Concurrent (ThreadId,forkIO)
import Control.Concurrent.STM(TQueue,atomically)
import Control.Monad (replicateM,return,mapM_)
import Control.Monad.IO.Class (liftIO)
import Data.Acid (openLocalState,openLocalStateFrom)
import Data.Function (($),(.),flip)
import Data.List (concat,(++))
import Data.Maybe (Maybe,maybe)
import System.IO (IO,FilePath,putStrLn)
import System.Random (StdGen,getStdGen)
import Text.Show (Show,show)

data HubbubConfig = HubbubConfig {
  subscriptionThreads::Int
  , publicationThreads::Int
  , distributionThreads::Int
  , serverUrl::ServerUrl
  }

data HubbubAcidConfig = HubbubAcidConfig {
  filePath :: Maybe FilePath
  }

data HubbubEnv = HubbubEnv {
  subscriptionThreadIds::[ThreadId]
  , publicationThreadIds::[ThreadId]
  , distributionThreadIds::[ThreadId]
  , subscriptionQueue::TQueue SubscriptionEvent
  , publicationQueue::TQueue PublicationEvent
  , distributionQueue::TQueue DistributionEvent
  , subscriptionDbApi::SubscriptionDbApi
  }

initializeHubbubAcid :: HubbubConfig -> HubbubAcidConfig -> IO HubbubEnv
initializeHubbubAcid conf acidConf = do
  acid <- maybe openLocalState openLocalStateFrom (filePath acidConf) emptyDb
  initializeHubbub conf $ acidDbApi acid

shutdownHubbub :: HubbubEnv -> IO ()
shutdownHubbub = shutdownDb . subscriptionDbApi

subscribe ::
  HubbubEnv ->
  Topic ->
  Callback ->
  LeaseSeconds ->
  Maybe Secret ->
  Maybe From ->
  IO ()
subscribe env t cb ls s f = atomically $ Q.subscribe (subscriptionQueue env) ev
  where ev = Subscribe t cb ls firstAttempt s f

unsubscribe :: HubbubEnv -> Topic -> Callback -> IO ()
unsubscribe env t cb = atomically $ Q.subscribe (subscriptionQueue env) ev
  where ev = Unsubscribe t cb firstAttempt

publish :: HubbubEnv -> Topic -> IO ()
publish env t =
  atomically . Q.publish (publicationQueue env) $ PublicationEvent t firstAttempt

--------------------------------------------------------------------------------
--- Private Stuff Below
--------------------------------------------------------------------------------

firstAttempt :: AttemptCount
firstAttempt = AttemptCount 1

initializeHubbub :: HubbubConfig -> SubscriptionDbApi -> IO HubbubEnv
initializeHubbub c dbApi = do
  rng <- getStdGen
  sQ  <- atomically emptySubscriptionQueue
  pQ  <- atomically emptyPublicationQueue
  dQ  <- atomically emptyDistributionQueue
  sTs <- startNThreads (subscriptionThreads c) (subscriptionThread rng dbApi sQ)
  pTs <- startNThreads (publicationThreads c)  (publicationThread dbApi dQ pQ)
  dTs <- startNThreads (distributionThreads c) (distributionThread sUrl dQ)
  return $ HubbubEnv sTs pTs dTs sQ pQ dQ dbApi
  where
    sUrl = serverUrl c

subscriptionThread :: StdGen -> SubscriptionDbApi -> TQueue SubscriptionEvent -> IO ()
subscriptionThread rng api = subscriptionLoop handleEvent logError
  where
    handleEvent = doSubscriptionEvent rng api
    logError ev err requeued = return ()

publicationThread ::
  SubscriptionDbApi ->
  TQueue DistributionEvent ->  
  TQueue PublicationEvent ->
  IO ()
publicationThread api distQ = publicationLoop handleEvent logError
  where
    handleEvent ev = do
      distEvs <- doPublicationEvent api ev
      liftIO $ atomically $ mapM_ (Q.distribute distQ) distEvs
      
    logError ev err requeued = return ()

distributionThread :: ServerUrl -> TQueue DistributionEvent -> IO ()
distributionThread surl = distributionLoop handleEvent logError
  where
    handleEvent = doDistributionEvent surl
    logError ev err requeued = return ()

logError :: (Show a,Show e) => a -> e -> Maybe RetryDelay -> IO ()
logError event err retryDelay = putStrLn $ concat
           [ "Got an error processing event '"
           , show event
           , "'. Error was '"
           , show err
           , "'. "
           , retryMessage
           ]
  where
    retryMessage = maybe retryDiscarded retryScheduled retryDelay
    retryScheduled rt = concat [
      " It will be retried in "
      , show . retryDelaySeconds $ rt
      , " seconds"
      ]
    retryDiscarded = " It has failed too many times and has been discarded."

startNThreads :: Int -> IO () -> IO [ThreadId]
startNThreads n = replicateM n . forkIO 
