module Network.Hubbub.Hmac (hmacBody) where

import Network.Hubbub.SubscriptionDb (Secret(Secret))

import Control.Monad (join)
import Data.ByteString.UTF8 (fromString)
import qualified Data.ByteString as Bs
import qualified Data.ByteString.Lazy as BsL
import Data.Function ((.),($))
import Data.List (map)
import Data.Text.Encoding (encodeUtf8)
import Data.HMAC (hmac_sha1)
import Text.Bytedump (hexString)

hmacBody :: Secret -> BsL.ByteString -> Bs.ByteString 
hmacBody s bs = fromString . join . map hexString $ hmacBytes 
  where
    hmacBytes = hmac_sha1 (secretToOctets s) (BsL.unpack bs)
    secretToOctets (Secret t) = Bs.unpack $ encodeUtf8 t 
