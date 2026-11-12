-- macOS adapter prototype. The window stack is the unmodified upstream
-- XMonad.StackSet; geometry follows XMonad.Layout.tile.
import qualified XMonad.StackSet as W
import XMonad.Geometry (Rect(..), tile)
import System.Environment (getArgs)
import Text.Read (readMaybe)
import Control.Monad (guard)

main :: IO ()
main = do
  args <- getArgs
  case traverse readMaybe args :: Maybe [Double] of
    Just [x,y,w,h,count,masters,ratio] -> do
      let n = floor count; m = floor masters
      guard (n >= 0 && m >= 0 && ratio >= 0 && ratio <= 1)
      let stack = W.differentiate [0..n-1]
          windows = maybe [] W.integrate stack
          rectangles = tile (toRational ratio) (Rect (round x) (round y) (round w) (round h)) m n
      mapM_ (\(_, Rect a b c d) -> putStrLn $ unwords $ map show [a,b,c,d]) (zip windows rectangles)
    _ -> fail "expected x y width height count masters ratio"
