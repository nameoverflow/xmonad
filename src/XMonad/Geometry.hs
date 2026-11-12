-- | Platform-independent rectangle splitting used by XMonad's Tall layout.
module XMonad.Geometry (Rect(..), tile, splitVertically) where

data Rect = Rect !Int !Int !Int !Int deriving (Eq, Show)

-- | Split the screen into master and secondary columns, as in XMonad.Layout.
tile :: Rational -> Rect -> Int -> Int -> [Rect]
tile f r@(Rect x y w h) nmaster n
    | n <= nmaster || nmaster == 0 = splitVertically n r
    | otherwise = splitVertically nmaster left ++ splitVertically (n - nmaster) right
  where
    leftWidth = floor (fromIntegral w * f)
    left = Rect x y leftWidth h
    right = Rect (x + leftWidth) y (w - leftWidth) h

splitVertically :: Int -> Rect -> [Rect]
splitVertically n r | n < 2 = [r]
splitVertically n (Rect x y w h) = Rect x y w small : splitVertically (n - 1) (Rect x (y + small) w (h - small))
  where small = h `div` n
