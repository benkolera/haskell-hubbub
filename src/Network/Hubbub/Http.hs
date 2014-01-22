module Network.Hubbub.Http 
  ( HttpError(..)
  , ServerUrl(ServerUrl)
  , verifySubscriptionEvent
  , getPublishedResource
  , distributeResource  
  ) where

import Network.Hubbub.Hmac (hmacBody)
import Network.Hubbub.SubscriptionDb 
  ( Callback(Callback)
  , HttpResource (HttpResource)
  , Topic (Topic)
  , fromCallback
  , fromTopic
  , httpResourceToText
  , httpResourceQueryString
  )
  
import Network.Hubbub.Queue
  ( DistributionEvent
  , ContentType(ContentType)
  , LeaseSeconds(LeaseSeconds)
  , PublicationEvent
  , ResourceBody(ResourceBody)
  , SubscriptionEvent(Subscribe,Unsubscribe)
  , distributionBody
  , distributionCallback
  , distributionContentType
  , distributionSecret
  , distributionTopic
  , fromContentType
  , fromResourceBody
  , publicationTopic
  )
  
import Prelude (IO,undefined,Int)
import Control.Arrow ((&&&))
import Control.Applicative ((<$>))
import Control.Error (EitherT(EitherT),fmapL,left,right,handleT)
import Control.Exception (try)
import Data.Bool (Bool(False),(&&),not)
import Data.CaseInsensitive (mk)
import Data.Char (chr)
import qualified Data.ByteString      as Bs
import qualified Data.ByteString.Lazy as BsL 
import Data.Default (def)
import Data.Either (Either)
import Data.Function (($),(.),const)
import Data.Functor (fmap)
import Data.Eq ((==),Eq)
import Data.List (map,take,find,filter,elem,(++))
import Data.Maybe (Maybe(Just,Nothing),fromMaybe,maybe)
import Data.Ord ((<=),(>=))
import Data.Text (Text,pack)
import Data.Text.Encoding (encodeUtf8)
import Data.Tuple (fst,snd)
import Network.HTTP.Conduit 
  ( HttpException
  , Request
  , RequestBody(RequestBodyLBS)    
  , Response
  , checkStatus
  , httpLbs    
  , host
  , method
  , path
  , port
  , queryString
  , responseBody
  , responseHeaders
  , responseStatus
  , requestBody
  , requestHeaders
  , secure
  , withManager
  )
import Network.HTTP.Types ( Status(Status) , statusCode , hContentType) 
import Text.Show (Show,show)
import System.Random (RandomGen,randomRs)

data HttpError =
  ConduitException HttpException 
  | NotFound Request
  | ServerError Request Bs.ByteString 
  | NotOk Request Int Bs.ByteString
  deriving (Show)

newtype ServerUrl = ServerUrl HttpResource

type HttpCall a = EitherT HttpError IO a

getPublishedResource ::
  PublicationEvent ->
  HttpCall (Maybe ContentType,ResourceBody)
getPublishedResource ev =
  fmap
    ((fmap ContentType . contentType) &&& (ResourceBody . responseBody)) 
    (doHttp (httpResourceToRequest . fromTopic . publicationTopic $ ev))
  where
    contentType :: Response BsL.ByteString -> Maybe Bs.ByteString
    contentType = fmap snd . find ((== hContentType) . fst) . responseHeaders

distributeResource :: DistributionEvent -> ServerUrl -> HttpCall ()
distributeResource ev (ServerUrl serverRes) =
  const () <$> doHttp publishReq
  where
    resource = httpResourceToRequest . fromCallback . distributionCallback $ ev
    body     = fromResourceBody . distributionBody $ ev
    contentT = fromMaybe "text/html" . fmap fromContentType . distributionContentType $ ev
    topicRes = fromTopic . distributionTopic $ ev
    
    headers  =
      (hContentType,contentT) :
      (mk "Link", linkHeaderValue) :
      maybe [] ((:[]) . hmacHeader) hmacSig
      
    publishReq = resource {
      method = "POST" 
      , requestBody = RequestBodyLBS body
      , requestHeaders = headers
      }
                 
    hmacSig = fmap (`hmacBody` body) . distributionSecret $ ev
    hmacHeader sig = (mk "X-Hub-Signature", sig)
    linkHeaderValue = Bs.intercalate "," [
      resToLink topicRes "self"
      , resToLink serverRes "hub"
      ]
    resToLink res rel = Bs.concat [
      "<"
      , encodeUtf8 . httpResourceToText $ res
      , ">; rel=\""
      , rel
      , "\""
      ]
        
      
verifySubscriptionEvent :: RandomGen r =>
  r ->
  SubscriptionEvent ->
  HttpCall Bool
verifySubscriptionEvent rng ev = case ev of
  (Subscribe t c ls _ _ _) -> check t c "subscribe" (Just ls)
  (Unsubscribe t c _)      -> check t c "unsubscribe" Nothing
  where
    check :: Topic -> Callback -> Text -> Maybe LeaseSeconds -> HttpCall Bool
    check (Topic t) (Callback c) m ls = handleT hush404 $
      checkChallenge <$> doHttp (httpResourceToRequest $ addQueryParams t m ls c)
      
    -- TODO: This is crap. Should write a lens for HttpResource.
    addQueryParams t m ls (HttpResource s h prt pth qps) =
      HttpResource s h prt pth $
        filter (not . isHubHeader) qps ++ (
          ("hub.mode", m) :
          ("hub.topic", httpResourceToText t ) :
          ("hub.challenge",challenge) :
          maybe [] ((:[]) . leaseSecondHeader) ls
          )
    isHubHeader (hn,_) = hn `elem` ["hub.mode","hub.topic","hub.challenge"]
    leaseSecondHeader (LeaseSeconds s) = ("hub.leaseSeconds",pack . show $ s)
    checkChallenge c =
      ((statusCode . responseStatus $ c) == 200) &&
      (responseBody c == BsL.fromStrict (encodeUtf8 challenge))
    challenge = pack $ map chr $ take 20 (randomRs (65,90) rng)
    hush404 :: HttpError -> HttpCall Bool
    hush404 (NotFound _) = right False
    hush404 httpErr      = left httpErr

httpResourceToRequest :: HttpResource -> Request
httpResourceToRequest res@(HttpResource sec h prt pth _) = def {
  secure = sec
  , host = encodeUtf8 h
  , port = prt
  , path = encodeUtf8 pth
  , queryString = encodeUtf8 . httpResourceQueryString $ res
  , checkStatus = \ _ _ _ -> Nothing
  }

doHttp :: Request -> HttpCall (Response BsL.ByteString)
doHttp req = do
  res <- EitherT $ fmapL ConduitException <$> tryHttp
  processResponseStatus res
  where
    tryHttp :: IO (Either HttpException (Response BsL.ByteString))
    tryHttp = try . withManager . httpLbs $ req
    processResponseStatus res = case responseStatus res of
      (Status 404 _) -> left $ NotFound req
      (Status 500 s) -> left $ ServerError req s
      (Status c   s) -> if c >= 200 && c <= 299
                        then right res
                        else left $ NotOk req c s 
