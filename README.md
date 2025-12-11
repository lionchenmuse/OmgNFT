# NFTMarket

## 概述

NFT交易市场合约，支持ERC721 NFT的上架、购买和交易功能。

该合约实现了基于ERC20代币的NFT交易市场，包含手续费机制和订单管理系统。

## 核心功能

1. **NFT上架**：允许NFT所有者将NFT上架到市场进行销售
2. **NFT购买**：买家可以使用ERC20Enhanced代币购买市场上的NFT
3. **手续费机制**：平台从每笔交易中收取一定比例的手续费，计算公式：平台手续费 = max(交易金额 * 平台手续费百分比 / 10000, minimumFee)
4. **订单管理**：订单生命周期管理（待处理、已完成、已取消）
5. **权限控制**：基于NFT所有权和授权的访问控制

## 主要流程

1. 卖家调用`list()`方法上架NFT
2. 买家调用`buy()`方法发起购买，创建订单并支付手续费
3. 合约通过`transferWithCallback`机制完成资金和NFT的交换
4. `tokenReceived()`回调函数完成NFT转移并更新订单状态

## 安全特性

- 使用try/catch处理外部调用异常
- 完善的权限验证（所有权和授权检查）
- 订单状态一致性保证
- 管理员权限控制（手续费设置）

## 测试实现

本项目使用 Foundry 框架对 `NFTMarket` 合约进行全面测试，确保合约功能正确性和安全性。

### 测试覆盖范围

#### 1. 上架NFT测试 (`list`)
- ✅ `test_list_by_owner_successful`: 所有者上架自己的NFT（成功情况）
- ✅ `test_list_by_approved_successful`: 授权者上架NFT（成功情况）
- ✅ `test_list_by_approved_for_all_successful`: 批量授权后上架NFT（成功情况）
- ❌ `test_list_failed`: 
  - ❌ 使用零地址合约测试（失败情况）
  - ❌ 无效价格测试（低于最小费用，失败情况）
  - ❌ NFT不存在测试（失败情况）
  - ❌ 无授权用户上架NFT（失败情况）

#### 2. 购买NFT测试 (`buy`)
- ✅ `test_buy_successful`: 正常购买流程（成功情况）
- ❌ `test_buy_same_seller_and_buyer_failure`: 自己购买自己的NFT（失败情况）
- ❌ `test_repeatly_buy_failure`: 重复购买同一NFT（失败情况）
- ❌ 支付过多或者过少Token：由于`buy`方法不需要价格参数，所以不存在该项测试。

#### 3. 模糊测试 (Fuzz Testing)
- `testFuzz_list_and_buy`: 对价格和买家地址进行随机测试
- 价格范围：由于OmgNFT有最小费用设定，所以价格范围是最小费用~1000倍最小费用之间，即：`minimumFee ~ 1000 * minimumFee`
- 随机买家地址测试各种边界情况：假定不为零地址。

#### 4. 不可变测试 (Invariant Testing)（可选）

NFTMarket合约会收取手续费，无法做“不可能持有Token”的不变性测试，改成“永不可能持有NFT”的不变性测试。
- `invariant_neverOwnedAnyNFT`: 测试 `NFTMarket` 合约永远不会持有任何 `NFT`
- 使用 `randomBuy` 作为测试目标函数进行大规模状态测试.

#### 5. 其他测试
- `test_changeFeePercent_successful`: 修改手续费百分比（成功情况）
- `test_changeFeePercent_failed`: 改变手续费百分比（失败情况）
- `test_changeMinimumFee_successful`: 改变最小费用（成功情况）
- `test_changeMinimumFee_failed`: 改变最小费用（失败情况）

### 测试执行结果

运行以下命令执行测试：
```bash
 forge test --match-contract NFTMarket
[⠊] Compiling...
[⠑] Compiling 1 files with Solc 0.8.30
[⠘] Solc 0.8.30 finished in 607.52ms
Compiler run successful!

Ran 13 tests for test/NFTMarket.t.sol:NFTMarketTest
[PASS] invariant_neverOwnedAnyNFT() (runs: 256, calls: 128000, reverts: 37)

╭---------------+-----------+---------+---------+----------╮
| Contract      | Selector  | Calls   | Reverts | Discards |
+==========================================================+
| NFTMarketTest | randomBuy | 2478113 | 37      | 2350113  |
╰---------------+-----------+---------+---------+----------╯

[PASS] testFuzz_list_and_buy(uint256,address) (runs: 257, μ: 585943, ~: 586046)
[PASS] test_buy_same_seller_and_buyer() (gas: 551114)
[PASS] test_buy_successful() (gas: 545540)
[PASS] test_changeFeePercent_failed() (gas: 15074)
[PASS] test_changeFeePercent_successful() (gas: 19885)
[PASS] test_changeMinimumFee_failed() (gas: 15093)
[PASS] test_changeMinimumFee_successful() (gas: 19818)
[PASS] test_list_by_approved_for_all_successful() (gas: 325591)
[PASS] test_list_by_approved_successful() (gas: 321672)
[PASS] test_list_by_owner_successful() (gas: 291257)
[PASS] test_list_failed() (gas: 162086)
[PASS] test_repeatly_buy_failure() (gas: 534772)
Suite result: ok. 13 passed; 0 failed; 0 skipped; finished in 78.61s (78.79s CPU time)

Ran 1 test suite in 78.61s (78.61s CPU time): 13 tests passed, 0 failed, 0 skipped (13 total tests)
```

测试结果显示所有测试均通过，验证了 `NFTMarket` 合约的功能正确性和安全性，符合设计要求。

### 测试特点

1. **全面的权限测试**：验证了所有者、单次授权和批量授权等各种权限场景
2. **完整的错误处理**：对各种异常情况进行测试并验证错误信息
3. **模糊测试覆盖**：使用随机输入测试边界条件和异常路径
4. **不变性验证**：确保关键业务约束在所有操作中都得到维护

这些测试确保了 `NFTMarket` 合约的安全性和可靠性，为生产环境部署提供了保障。