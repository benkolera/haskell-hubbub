module Network.Hubbub.Http 
  ( HttpError(..)
  , ServerUrl(ServerUrl)
  , checkSubscription
  , getPublishedResource
  , publishResource  
  ) where

import Network.Hubbub.Hmac (hmacBody)
import Network.Hubbub.SubscriptionDb 
  ( Callback(Callback)
  , HttpResource (HttpResource)
  , Secret 
  , Topic (Topic)    
  , httpResourceToText
  , httpResourceQueryString
  )
  
import Network.Hubbub.Queue (SubscriptionEvent (SubscriptionEvent),modeToText)
  
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
import Data.Maybe (Maybe(Nothing),fromMaybe,maybe)
import Data.Ord ((<=),(>=))
import Data.Text (pack)
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
import Text.Show (Show)
import System.Random (RandomGen,randomRs)

data HttpError =
  ConduitException HttpException 
  | NotFound Request
  | ServerError Request Bs.ByteString 
  | NotOk Request Int Bs.ByteString
  deriving (Show)

newtype ServerUrl = ServerUrl HttpResource

type HttpCall a = EitherT HttpError IO a

getPublishedResource :: Topic -> HttpCall (Maybe Bs.ByteString,BsL.ByteString)
getPublishedResource (Topic res) = 
  (contentType &&& responseBody) <$> doHttp (httpResourceToRequest res)
  where
    contentType = fmap snd . find ((== hContentType) . fst) . responseHeaders

publishResource ::
  Maybe Secret ->         -- ^ Secret used for HMAC signing
  Callback ->             -- ^ Subscriber callback URL
  Topic ->                -- ^ Topic that is being published
  ServerUrl ->            -- ^ Server Resource for self link
  Maybe Bs.ByteString ->  -- ^ Content type of published resource
  BsL.ByteString ->       -- ^ Body of resource
  HttpCall ()
publishResource sec (Callback cRes) (Topic tRes) (ServerUrl sRes) ct body =
  const () <$> doHttp publishReq
  where
    publishReq = (httpResourceToRequest cRes) {
      method = "POST"
      , requestBody = RequestBodyLBS body
      , requestHeaders =
        (hContentType,fromMaybe "text/html" ct) :
        (mk "Link", linkHeaderValue) :
        maybe [] ((:[]) . hmacHeader) hmacSig
      }
    hmacSig = fmap (`hmacBody` body) sec
    hmacHeader sig = (mk "X-Hub-Signature", sig)
    linkHeaderValue = Bs.intercalate "," [
      resToLink tRes "self"
      , resToLink sRes "hub"
      ]
    resToLink res rel = Bs.concat [
      "<"
      , encodeUtf8 . httpResourceToText $ res
      , ">; rel=\""
      , rel
      , "\""
      ]
        
      
checkSubscription :: RandomGen r => r -> SubscriptionEvent -> HttpCall Bool
checkSubscription rng (SubscriptionEvent (Topic tRes) (Callback cRes) m _ _ _) = 
  handleT hush404 $
    checkChallenge <$> doHttp (httpResourceToRequest $ addQueryParams cRes)
  where
    -- TODO: This is crap. Should write a lens for HttpResource.
    addQueryParams (HttpResource s h prt pth qps) =
      HttpResource s h prt pth $
        filter (not . isHubHeader) qps ++ [
          ("hub.mode", modeToText m)
          , ("hub.topic", httpResourceToText tRes )
          , ("hub.challenge",challenge)
          ] 
    isHubHeader (hn,_) = hn `elem` ["hub.mode","hub.topic","hub.challenge"]
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
