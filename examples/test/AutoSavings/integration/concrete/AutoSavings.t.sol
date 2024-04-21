// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {
    BaseIntegrationTest,
    ModuleKitHelpers,
    ModuleKitSCM,
    ModuleKitUserOp
} from "test/BaseIntegration.t.sol";
import { AutoSavings } from "src/AutoSavings/AutoSavings.sol";
import { MODULE_TYPE_EXECUTOR } from "modulekit/src/external/ERC7579.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { MockERC4626 } from "solmate/test/utils/mocks/MockERC4626.sol";
import { SENTINEL } from "sentinellist/SentinelList.sol";

contract AutoSavingsIntegrationTest is BaseIntegrationTest {
    using ModuleKitHelpers for *;
    using ModuleKitSCM for *;
    using ModuleKitUserOp for *;
    /*//////////////////////////////////////////////////////////////////////////
                                    CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    AutoSavings internal executor;

    MockERC20 internal token1;
    MockERC20 internal token2;
    MockERC4626 internal vault1;
    MockERC4626 internal vault2;

    /*//////////////////////////////////////////////////////////////////////////
                                    VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    address[] _tokens;

    /*//////////////////////////////////////////////////////////////////////////
                                      SETUP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        BaseIntegrationTest.setUp();

        executor = new AutoSavings();

        token1 = new MockERC20("USDC", "USDC", 18);
        vm.label(address(token1), "USDC");
        token1.mint(address(instance.account), 1_000_000);

        token2 = new MockERC20("wETH", "wETH", 18);
        vm.label(address(token2), "wETH");
        token2.mint(address(instance.account), 1_000_000);

        vault1 = new MockERC4626(token1, "vUSDC", "vUSDC");
        vault2 = new MockERC4626(token2, "vwETH", "vwETH");

        _tokens = new address[](2);
        _tokens[0] = address(token1);
        _tokens[1] = address(token2);

        AutoSavings.Config[] memory _configs = getConfigs();

        bytes memory data = abi.encode(_tokens, _configs);

        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: address(executor),
            data: data
        });
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     UTILS
    //////////////////////////////////////////////////////////////////////////*/

    function getConfigs() public returns (AutoSavings.Config[] memory _configs) {
        _configs = new AutoSavings.Config[](2);
        _configs[0] = AutoSavings.Config(100, address(vault1), 0);
        _configs[1] = AutoSavings.Config(100, address(vault2), 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_OnInstallSetsConfigAndTokens() public {
        // it should set the config and tokens of the account
        bool isInitialized = executor.isInitialized(address(instance.account));
        assertTrue(isInitialized);

        AutoSavings.Config[] memory _configs = getConfigs();

        for (uint256 i; i < _tokens.length; i++) {
            (uint16 _percentage, address _vault, uint128 _sqrtPriceLimitX96) =
                executor.config(address(instance.account), _tokens[i]);
            assertEq(_percentage, _configs[i].percentage);
            assertEq(_vault, _configs[i].vault);
            assertEq(_sqrtPriceLimitX96, _configs[i].sqrtPriceLimitX96);
        }

        address[] memory tokens = executor.getTokens(address(instance.account));
        assertEq(tokens.length, _tokens.length);
    }

    function test_OnUninstallRemovesConfigAndTokens() public {
        // it should remove the config and tokens of the account
        instance.uninstallModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: address(executor),
            data: ""
        });

        bool isInitialized = executor.isInitialized(address(instance.account));
        assertFalse(isInitialized);

        for (uint256 i; i < _tokens.length; i++) {
            (uint16 _percentage, address _vault, uint128 _sqrtPriceLimitX96) =
                executor.config(address(instance.account), _tokens[i]);
            assertEq(_percentage, 0);
            assertEq(_vault, address(0));
            assertEq(_sqrtPriceLimitX96, 0);
        }

        address[] memory tokens = executor.getTokens(address(instance.account));
        assertEq(tokens.length, 0);
    }

    function test_SetConfig() public {
        // it should add a config and token
        address token = address(2);
        AutoSavings.Config memory config = AutoSavings.Config(10, address(1), 100);

        instance.getExecOps({
            target: address(executor),
            value: 0,
            callData: abi.encodeWithSelector(AutoSavings.setConfig.selector, token, config),
            txValidator: address(instance.defaultValidator)
        }).execUserOps();

        (uint16 _percentage, address _vault, uint128 _sqrtPriceLimitX96) =
            executor.config(address(instance.account), token);
        assertEq(_percentage, config.percentage);
        assertEq(_vault, config.vault);
        assertEq(_sqrtPriceLimitX96, config.sqrtPriceLimitX96);
    }

    function test_DeleteConfig() public {
        // it should delete a config and token
        AutoSavings.Config[] memory _configs = getConfigs();

        (uint16 _percentage, address _vault, uint128 _sqrtPriceLimitX96) =
            executor.config(address(instance.account), _tokens[1]);
        assertEq(_percentage, _configs[1].percentage);
        assertEq(_vault, _configs[1].vault);
        assertEq(_sqrtPriceLimitX96, _configs[1].sqrtPriceLimitX96);

        instance.getExecOps({
            target: address(executor),
            value: 0,
            callData: abi.encodeWithSelector(AutoSavings.deleteConfig.selector, SENTINEL, _tokens[1]),
            txValidator: address(instance.defaultValidator)
        }).execUserOps();

        (_percentage, _vault, _sqrtPriceLimitX96) =
            executor.config(address(instance.account), _tokens[1]);
        assertEq(_percentage, 0);
        assertEq(_vault, address(0));
        assertEq(_sqrtPriceLimitX96, 0);
    }

    function test_AutoSave_WithUnderlyingToken() public {
        // it should deposit the underlying token into the vault
        uint256 amount = 100;
        uint256 prevBalance = token1.balanceOf(address(vault1));

        instance.getExecOps({
            target: address(executor),
            value: 0,
            callData: abi.encodeWithSelector(AutoSavings.autoSave.selector, token1, amount),
            txValidator: address(instance.defaultValidator)
        }).execUserOps();

        assertEq(token1.balanceOf(address(instance.account)), 999_900);
        assertEq(token1.balanceOf(address(vault1)), prevBalance + amount);
    }

    function test_AutoSave_WithNonUnderlyingToken() public {
        // it should deposit the underlying token into the vault
        // TODO
        assertFalse(true);
    }
}