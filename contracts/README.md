# starlinkminer

StarLink Miner project

## Flow chart
 code from http://asciiflow.com/

```javascript

                                    +------------+
                   bidding words    |            |
                   +----------------+   Wallet   |
                   |                |            |
                   |                +-----+--+---+
                   v                      |  |
            +------+-----+        <-------+  +----->+
            |            |        |                 |
        +---+  WordFund  +<---+   |   deposit       |
        |   |            |    |   |   withdraw      |
deposit |   +------------+    |   |   claim         |
        |              bidding|   |                 |
        |                     |   |                 |
 +------v-----+        +------+---v-+        +------v-----+
 |            |        |            |        |            |
 |  StarPools |        |  StarPools |        |  StarPools |
 |            |        |            |        |            |
 +------+-+---+        +--+---+-----+        +------+-----+
        | |               ^   |                     |
        | +---------------+   |                     |
        |      refund         |                     |
        |              +------v-----+               |
        |              |            |               |
        +------------->+  SLN Token <---------------+
                       |            |
                       +------------+
```

## Modules

### Wallet
User wallet, such as metamask

### WordFund
Word management contract, used for word NFT auction, management

### StarPools
Various collateral mining pools for basic mining

### SLNToken
User maintains the generation of SLN Token and the progress of mining


## Key Methods
