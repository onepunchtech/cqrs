{-# LANGUAGE DeriveGeneric #-}

module Lib
    (
    ) where

import           Control.Concurrent
import           Control.Concurrent.STM
import           Control.Concurrent.STM.TMChan
import           Control.Exception              (finally)
import           Control.Monad                  (forever, void)
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
  connId <- nextRandom
  finally (connect connId conn subState) (atomically $ disconnect connId subState)

type QueryId = UUID
type ConnId = UUID

data CQRSOps = JoinQuery T.Text
             | LeaveQuery QueryId
             | Command T.Text
             deriving (Generic)

data QueryRes = Res { queryId  :: QueryId
                    , queryRes :: BS.ByteString
                    }
              | Joined QueryId
              | Left QueryId


instance FromJSON CQRSOps

connect connId conn subState = forever $ do
  msg <- WS.receiveData conn
  let (Just op) = decode msg :: Maybe CQRSOps
  case op of
    JoinQuery q    -> do
      (qId, chan) <- joinQuery q connId subState
      void $ forkIO $ forward conn qId chan
    LeaveQuery qId ->
      atomically $ leaveQuery connId qId subState
    Command command        -> handleCommand command

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

handleCommand :: T.Text -> IO ()
handleCommand _ = return ()


leaveQuery :: ConnId -> QueryId -> QuerySubscriptionState -> STM ()
leaveQuery connId qId subState = do
  st <- readTVar subState
  updatedSubs <- case M.lookup connId st of
        Just subs -> do
          case M.lookup qId subs of
            Just chan -> closeTMChan chan
            Nothing   -> return ()
          return $ M.delete qId subs
        Nothing   -> return M.empty

  writeTVar subState (M.insert connId updatedSubs st)


disconnect :: ConnId -> QuerySubscriptionState -> STM ()
disconnect connId subState = do
  modifyTVar subState (M.delete connId)

