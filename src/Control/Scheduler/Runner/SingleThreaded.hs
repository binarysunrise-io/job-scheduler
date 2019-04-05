{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE RecordWildCards       #-}

module Control.Scheduler.Runner.SingleThreaded (
  SingleThreaded,
  setSchedulerEndTime
) where

import           Control.Monad                (when)
import           Control.Monad.State.Strict   (evalStateT, gets, modify)
import           Control.Scheduler.Class      (MonadJobs (..))
import           Control.Scheduler.Task.Class (Job (..))
import           Control.Scheduler.Time       (ScheduledTime (..))
import           Control.Scheduler.Type       (RunnableScheduler (..),
                                               Scheduler, unScheduler)
import qualified Data.PQueue.Prio.Min         as PQ


data SingleThreaded d = SingleThreaded {
  stJobQueue :: PQ.MinPQueue ScheduledTime (Job d),
  stEndTime  :: Maybe ScheduledTime
}

setSchedulerEndTime :: Monad m => ScheduledTime -> Scheduler SingleThreaded d m ()
setSchedulerEndTime endTime = modify $ \schedulerState@SingleThreaded{..} ->
                                          schedulerState { stEndTime = Just endTime }

stInsert :: Monad m => ScheduledTime -> Job d -> Scheduler SingleThreaded d m ()
stInsert executesAt item =
  modify $ \schedulerState@SingleThreaded{..} ->
    schedulerState {
      stJobQueue = PQ.insert executesAt item stJobQueue
    }

stPeek :: Monad m => Scheduler SingleThreaded d m (Maybe (ScheduledTime, Job d))
stPeek = do
  jobQueue <- gets stJobQueue
  return (fst <$> PQ.minViewWithKey jobQueue)

stDrop :: Monad m => Scheduler SingleThreaded d m ()
stDrop = modify $ \schedulerState@SingleThreaded{..} -> schedulerState { stJobQueue = PQ.deleteMin stJobQueue }

instance Monad m => MonadJobs d (Scheduler SingleThreaded d m) where
  pushQueue executesAt item = do
    mbEndTime <- gets stEndTime

    case mbEndTime of
      Nothing      -> stInsert executesAt item
      Just endTime -> when (executesAt <= endTime) (stInsert executesAt item)

  popQueue = stPeek

  execute action = action >> stDrop

  enumerate = PQ.toList <$> gets stJobQueue

instance RunnableScheduler SingleThreaded where
  runScheduler actions = evalStateT (unScheduler actions) (SingleThreaded PQ.empty Nothing)
