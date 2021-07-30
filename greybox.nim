var counter : float
while counter < 500:
  counter += 1/3;
  if counter - counter.int.float > 0.99:
    counter = counter.int.float + 1
  echo counter