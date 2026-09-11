bottle_word <- function(n) {
  if (n == 1) "bottle" else "bottles"
}

bottle_phrase <- function(n) {
  if (n == 0) {
    "no more bottles"
  } else {
    paste(n, bottle_word(n))
  }
}

for (n in 99:1) {
  current <- bottle_phrase(n)
  next_count <- if (n - 1 == 0) "no more bottles" else bottle_phrase(n - 1)

  cat(sprintf("%s of beer on the wall, %s of beer.\n", current, current))
  cat(sprintf("Take one down and pass it around, %s of beer on the wall.\n", next_count))
  cat("\n")
}

cat("No more bottles of beer on the wall, no more bottles of beer.\n")
cat("Go to the store and buy some more, 99 bottles of beer on the wall.\n")
