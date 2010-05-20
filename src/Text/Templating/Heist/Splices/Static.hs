{-# LANGUAGE OverloadedStrings #-}

module Text.Templating.Heist.Splices.Static where

------------------------------------------------------------------------------
import           Control.Concurrent
import           Control.Monad
import           Control.Monad.Trans
import           Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as B
import           Data.IORef
import qualified Data.Map as Map
import           Data.Map (Map)
import           Data.Maybe
import qualified Data.Set as Set
import           System.Random
import           Text.XML.Expat.Cursor
import           Text.XML.Expat.Tree hiding (Node)


------------------------------------------------------------------------------
import           Text.Templating.Heist.Internal


------------------------------------------------------------------------------
-- | The "static" splice ensures that its contents are evaluated once and then
-- cached.  The cached contents are returned every time the splice is
-- referenced.
staticImpl :: (MonadIO m)
           => MVar (Map ByteString Template)
           -> TemplateMonad m Template
staticImpl mv = do
    tree <- getParamNode
    let i = fromJust $ getAttribute tree "id"

    mp <- liftIO $ readMVar mv

    (mp',ns) <- do
                   let mbn = Map.lookup i mp
                   case mbn of
                       Nothing -> do
                           nodes' <- runNodeList $ getChildren tree
                           return $! (Map.insert i nodes' mp, nodes')
                       (Just n) -> do
                           stopRecursion
                           return $! (mp,n)

    liftIO $ modifyMVar_ mv (const $ return mp')

    return ns


------------------------------------------------------------------------------
-- | Modifies a TemplateState to include a "static" tag.
bindStaticTag :: MonadIO m
              => TemplateState m
              -> IO (TemplateState m, MVar (Map ByteString [Node]))
bindStaticTag ts = do
    sr <- newIORef $ Set.empty
    mv <- newMVar Map.empty

    return $ (addOnLoadHook (assignIds sr) $
                bindSplice "static" (staticImpl mv) ts,
              mv)

  where
    generateId :: IO Int
    generateId = getStdRandom random

    assignIds setref = mapM f
        where
          f node = g $ fromTree node

          getId = do
              i  <- liftM (B.pack . show) generateId
              st <- readIORef setref
              if Set.member i st
                then getId
                else do
                    writeIORef setref $ Set.insert i st
                    return i

          g curs = do
              let node = current curs
              curs' <- if getName node == "static"
                         then do
                             i <- getId
                             return $ modifyContent (setAttribute "id" i) curs
                         else return curs
              let mbc = nextDF curs'
              maybe (return $ toTree curs') g mbc



