{-# LANGUAGE DeriveGeneric #-}

module Lib
    (
    ) where

import           Control.Concurrent
import           Control.Concurrent.STM
import           Control.Concurrent.STM.TMChan
import           Control.Exception              (finally)
import           Control.Monad                  (forever)
import           Data.Aeson
import qualified Data.ByteString.Lazy           as BS
import qualified Data.Map                       as M
import           Data.Maybe
import qualified Data.Text                      as T
import           Data.UUID
import           Data.UUID.V4
import           GHC.Generics
import qualified Network.Wai
import qualified Network.Wai.Handler.WebSockets as WaiWS
import qualified Network.WebSockets             as WS

wsApp :: QuerySubscriptionState -> WS.ServerApp
wsApp subState pending = do
  conn <- WS.acceptRequest pending
  WS.forkPingThread conn 30
  finally (connect subState conn) disconnect
  where
    connect = undefined
    disconnect = undefined

type QueryId = UUID
type ConnId = UUID

data CQRSOps = JoinQuery T.Text
             | LeaveQuery QueryId
             | Write T.Text
             deriving (Generic)

data QueryRes = Res { queryId  :: QueryId
                    , queryRes :: BS.ByteString
                    }
              | Joined QueryId
              | Left QueryId


instance FromJSON CQRSOps

connect subState conn = forever $ do
  msg <- WS.receiveData conn
  let (Just op) = decode msg :: Maybe CQRSOps
  case op of
    JoinQuery q    -> do
      connId <- nextRandom
      (qId, chan) <- joinQuery q connId subState
      forward conn qId chan
    LeaveQuery qId -> return ()
    Write v        -> return ()

  where
    forward conn qId chan = do
      output <- atomically $ readTMChan chan
      case output of
        Just res -> do
          WS.sendTextData conn res
          forward conn qId chan
        Nothing -> return ()

type QuerySubscriptionState = TVar (M.Map ConnId (M.Map QueryId (TMChan BS.ByteString)))

joinQuery :: T.Text -> ConnId -> QuerySubscriptionState -> IO (QueryId, (TMChan BS.ByteString))
joinQuery query connId subState = do
  chan <- newTMChanIO
  qId <- nextRandom
  atomically $ do
    modifyTVar subState (M.alter (Just . maybe M.empty (M.insert qId chan)) connId)

  return (qId, chan)




leaveQuery :: QueryId -> QuerySubscriptionState -> STM ()
leaveQuery = undefined

disconnect :: ConnId -> QuerySubscriptionState -> STM ()
disconnect = undefined

