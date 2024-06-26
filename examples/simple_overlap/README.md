# Simple overlap case

1, 2, 3, 4 are loads with value 1. 5 and 6 are backup feeders with max power 2.

```txt
 mf --- fail--- 1 --- 2 --- 3 --- 4
                      |     |
                      5     6
```

The case we want to look at is where there is a failure between mf and fail. Then those nodes are cut off the network giving somehing like this

```txt
 1 --- 2 --- 3 --- 4
       |     |
       5     6
```

5 and 6 are backup power sources that each can supply two loads. The solution should be that 5 supplies 1 and 2, and 6 supplies 3 and 4.

```txt
 1 --- 2 -- | -- 3 --- 4
       |         |
       5         6
```

## To run example with visualization

Enter the julia repl

`] activate RelDist`

`] dev GLMakie`
