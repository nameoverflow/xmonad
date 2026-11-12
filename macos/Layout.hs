-- macOS adapter prototype. The window stack is the unmodified upstream
-- XMonad.StackSet; geometry follows XMonad.Layout.tile.
import qualified XMonad.StackSet as W
import System.Environment (getArgs)
import Text.Read (readMaybe)
import Control.Monad (guard)

data Rect = Rect Int Int Int Int deriving Show
splitV :: Int -> Rect -> [Rect]
splitV n r | n < 2 = [r]
splitV n (Rect x y w h) = Rect x y w small : splitV (n-1) (Rect x (y+small) w (h-small)) where small = h `div` n
layout :: Rational -> Rect -> Int -> Int -> [Rect]
layout f r@(Rect x y w h) m n
  | n <= 0 = []
  | n <= m || m == 0 = splitV n r
  | otherwise = splitV m (Rect x y left h) ++ splitV (n-m) (Rect (x+left) y (w-left) h)
  where left = floor (fromIntegral w * f)
main :: IO ()
main = do
  args <- getArgs
  case traverse readMaybe args :: Maybe [Double] of
    Just [x,y,w,h,count,masters,ratio] -> do
      let n = floor count; m = floor masters
      guard (n >= 0 && m >= 0 && ratio >= 0 && ratio <= 1)
      let stack = W.differentiate [0..n-1]
          windows = maybe [] W.integrate stack
          rectangles = layout (toRational ratio) (Rect (round x) (round y) (round w) (round h)) m n
      mapM_ (\(_, Rect a b c d) -> putStrLn $ unwords $ map show [a,b,c,d]) (zip windows rectangles)
    _ -> fail "expected x y width height count masters ratio"
