# Using Mox for Testing in Pleroma

## Introduction

This guide explains how to use [Mox](https://hexdocs.pm/mox/Mox.html) for testing in Pleroma and how to migrate existing tests from Mock/meck to Mox. Mox is a library for defining concurrent mocks in Elixir that offers several key advantages:

- **Async-safe testing**: Mox supports concurrent testing with `async: true`
- **Explicit contract through behaviors**: Enforces implementation of behavior callbacks
- **No module redefinition**: Avoids runtime issues caused by redefining modules
- **Expectations scoped to the current process**: Prevents test state from leaking between tests

## Why Migrate from Mock/meck to Mox?

### Problems with Mock/meck

1. **Not async-safe**: Tests using Mock/meck cannot safely run with `async: true`, which slows down the test suite
2. **Global state**: Mocked functions are global, leading to potential cross-test contamination
3. **No explicit contract**: No guarantee that mocked functions match the actual implementation
4. **Module redefinition**: Can lead to hard-to-debug runtime issues

### Benefits of Mox

1. **Async-safe testing**: Tests can run concurrently with `async: true`, significantly speeding up the test suite
2. **Process isolation**: Expectations are set per process, preventing leakage between tests
3. **Explicit contracts via behaviors**: Ensures mocks implement all required functions
4. **Compile-time checks**: Prevents mocking non-existent functions
5. **No module redefinition**: Mocks are defined at compile time, not runtime

## Existing Mox Setup in Pleroma

Pleroma already has a basic Mox setup in the `Pleroma.DataCase` module, which handles some common mocking scenarios automatically. Here's what's included:

### Default Mox Configuration

The `setup` function in `DataCase` does the following:

1. Sets up Mox for either async or non-async tests
2. Verifies all mock expectations on test exit
3. Stubs common dependencies with their real implementations

```elixir
# From test/support/data_case.ex
setup tags do
  setup_multi_process_mode(tags)
  setup_streamer(tags)
  stub_pipeline()

  Mox.verify_on_exit!()

  :ok
end
```

### Async vs. Non-Async Test Setup

Pleroma configures Mox differently depending on whether your test is async or not:

```elixir
def setup_multi_process_mode(tags) do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Pleroma.Repo)

  if tags[:async] do
    # For async tests, use process-specific mocks and stub CachexMock with NullCache
    Mox.stub_with(Pleroma.CachexMock, Pleroma.NullCache)
    Mox.set_mox_private()
  else
    # For non-async tests, use global mocks and stub CachexMock with CachexProxy
    Ecto.Adapters.SQL.Sandbox.mode(Pleroma.Repo, {:shared, self()})

    Mox.set_mox_global()
    Mox.stub_with(Pleroma.CachexMock, Pleroma.CachexProxy)
    clear_cachex()
  end

  :ok
end
```

### Default Pipeline Stubs

Pleroma automatically stubs several core components with their real implementations:

```elixir
def stub_pipeline do
  Mox.stub_with(Pleroma.Web.ActivityPub.SideEffectsMock, Pleroma.Web.ActivityPub.SideEffects)
  Mox.stub_with(Pleroma.Web.ActivityPub.ObjectValidatorMock, Pleroma.Web.ActivityPub.ObjectValidator)
  Mox.stub_with(Pleroma.Web.ActivityPub.MRFMock, Pleroma.Web.ActivityPub.MRF)
  Mox.stub_with(Pleroma.Web.ActivityPub.ActivityPubMock, Pleroma.Web.ActivityPub.ActivityPub)
  Mox.stub_with(Pleroma.Web.FederatorMock, Pleroma.Web.Federator)
  Mox.stub_with(Pleroma.ConfigMock, Pleroma.Config)
  Mox.stub_with(Pleroma.StaticStubbedConfigMock, Pleroma.Test.StaticConfig)
  Mox.stub_with(Pleroma.StubbedHTTPSignaturesMock, Pleroma.Test.HTTPSignaturesProxy)
end
```

This means that by default, these mocks will behave like their real implementations unless you explicitly override them with expectations in your tests.

### Understanding Config Mock Types

Pleroma has three different Config mock implementations, each with a specific purpose and different characteristics regarding async test safety:

#### 1. ConfigMock

- Defined in `test/support/mocks.ex` as `Mox.defmock(Pleroma.ConfigMock, for: Pleroma.Config.Getting)`
- It's stubbed with the real `Pleroma.Config` by default in `DataCase`: `Mox.stub_with(Pleroma.ConfigMock, Pleroma.Config)`
- This means it falls back to the normal configuration behavior unless explicitly overridden
- Used for general mocking of configuration in tests where you want most config to behave normally
- ⚠️ **NOT ASYNC-SAFE**: Since it's stubbed with the real `Pleroma.Config`, it modifies global application state
- Can not be used in tests with `async: true`

#### 2. StaticStubbedConfigMock

- Defined in `test/support/mocks.ex` as `Mox.defmock(Pleroma.StaticStubbedConfigMock, for: Pleroma.Config.Getting)`
- It's stubbed with `Pleroma.Test.StaticConfig` (defined in `test/test_helper.exs`)
- `Pleroma.Test.StaticConfig` creates a completely static configuration snapshot at the start of the test run:
  ```elixir
  defmodule Pleroma.Test.StaticConfig do
    @moduledoc """
    This module provides a Config that is completely static, built at startup time from the environment. 
    It's safe to use in testing as it will not modify any state.
    """

    @behaviour Pleroma.Config.Getting
    @config Application.get_all_env(:pleroma)

    def get(path, default \\ nil) do
      get_in(@config, path) || default
    end
  end
  ```
- Configuration is frozen at startup time and doesn't change during the test run
- ✅ **ASYNC-SAFE**: Never modifies global state since it uses a frozen snapshot of the configuration

#### 3. UnstubbedConfigMock

- Defined in `test/support/mocks.ex` as `Mox.defmock(Pleroma.UnstubbedConfigMock, for: Pleroma.Config.Getting)`
- Unlike the other two mocks, it's not automatically stubbed with any implementation in `DataCase`
- Starts completely "unstubbed" and requires tests to explicitly set expectations or stub it
- The most commonly used configuration mock in the test suite
- Often aliased as `ConfigMock` in individual test files: `alias Pleroma.UnstubbedConfigMock, as: ConfigMock`
- Set as the default config implementation in `config/test.exs`: `config :pleroma, :config_impl, Pleroma.UnstubbedConfigMock`
- Offers maximum flexibility for tests that need precise control over configuration values
- ✅ **ASYNC-SAFE**: Safe if used with `expect()` to set up test-specific expectations (since expectations are process-scoped)

#### Configuring Components to Use Specific Mocks

In `config/test.exs`, different components can be configured to use different configuration mocks:

```elixir
# Components using UnstubbedConfigMock
config :pleroma, Pleroma.Upload, config_impl: Pleroma.UnstubbedConfigMock
config :pleroma, Pleroma.User.Backup, config_impl: Pleroma.UnstubbedConfigMock
config :pleroma, Pleroma.Uploaders.S3, config_impl: Pleroma.UnstubbedConfigMock

# Components using StaticStubbedConfigMock (async-safe)
config :pleroma, Pleroma.Language.LanguageDetector, config_impl: Pleroma.StaticStubbedConfigMock
config :pleroma, Pleroma.Web.RichMedia.Helpers, config_impl: Pleroma.StaticStubbedConfigMock
config :pleroma, Pleroma.Web.Plugs.HTTPSecurityPlug, config_impl: Pleroma.StaticStubbedConfigMock
```

This allows different parts of the application to use the most appropriate configuration mocking strategy based on their specific needs.

#### When to Use Each Config Mock Type

- **ConfigMock**: ⚠️ For non-async tests only, when you want most configuration to behave normally with occasional overrides
- **StaticStubbedConfigMock**: ✅ For async tests where modifying global state would be problematic and a static configuration is sufficient
- **UnstubbedConfigMock**: ⚠️ Use carefully in async tests; set specific expectations rather than stubbing with implementations that modify global state

#### Summary of Async Safety

| Mock Type | Async-Safe? | Best Use Case |
|-----------|-------------|--------------|
| ConfigMock | ❌ No | Non-async tests that need minimal configuration overrides |
| StaticStubbedConfigMock | ✅ Yes | Async tests that need configuration values without modification |
| UnstubbedConfigMock | ⚠️ Depends | Any test with careful usage; set expectations rather than stubbing |

## Configuration in Async Tests

### Understanding `clear_config` Limitations

The `clear_config` helper is commonly used in Pleroma tests to modify configuration for specific tests. However, it's important to understand that **`clear_config` is not async-safe** and should not be used in tests with `async: true`.

Here's why:

```elixir
# Implementation of clear_config in test/support/helpers.ex
defmacro clear_config(config_path, temp_setting) do
  quote do
    clear_config(unquote(config_path)) do
      Config.put(unquote(config_path), unquote(temp_setting))
    end
  end
end

defmacro clear_config(config_path, do: yield) do
  quote do
    initial_setting = Config.fetch(unquote(config_path))

    unquote(yield)

    on_exit(fn ->
      case initial_setting do
        :error ->
          Config.delete(unquote(config_path))

        {:ok, value} ->
          Config.put(unquote(config_path), value)
      end
    end)

    :ok
  end
end
```

The issue is that `clear_config`:
1. Modifies the global application environment
2. Uses `on_exit` to restore the original value after the test
3. Can lead to race conditions when multiple async tests modify the same configuration

### Async-Safe Configuration Approaches

When writing async tests with Mox, use these approaches instead of `clear_config`:

1. **Dependency Injection with Module Attributes**:
   ```elixir
   # In your module
   @config_impl Application.compile_env(:pleroma, [__MODULE__, :config_impl], Pleroma.Config)
   
   def some_function do
     value = @config_impl.get([:some, :config])
     # ...
   end
   ```

2. **Mock the Config Module**:
   ```elixir
   # In your test
   Pleroma.ConfigMock
   |> expect(:get, fn [:some, :config] -> "test_value" end)
   ```

3. **Use Test-Specific Implementations**:
   ```elixir
   # Define a test-specific implementation
   defmodule TestConfig do
     def get([:some, :config]), do: "test_value"
     def get(_), do: nil
   end
   
   # In your test
   Mox.stub_with(Pleroma.ConfigMock, TestConfig)
   ```

4. **Pass Configuration as Arguments**:
   ```elixir
   # Refactor functions to accept configuration as arguments
   def some_function(config \\ nil) do
     config = config || Pleroma.Config.get([:some, :config])
     # ...
   end
   
   # In your test
   some_function("test_value")
   ```

By using these approaches, you can safely run tests with `async: true` without worrying about configuration conflicts.

## Setting Up Mox in Pleroma

### Step 1: Define a Behavior

Start by defining a behavior for the module you want to mock. This specifies the contract that both the real implementation and mocks must follow.

```elixir
# In your implementation module (e.g., lib/pleroma/uploaders/s3.ex)
defmodule Pleroma.Uploaders.S3.ExAwsAPI do
  @callback request(op :: ExAws.Operation.t()) :: {:ok, ExAws.Operation.t()} | {:error, term()}
end
```

### Step 2: Make Your Implementation Configurable

Modify your module to use a configurable implementation. This allows for dependency injection and easier testing.

```elixir
# In your implementation module
@ex_aws_impl Application.compile_env(:pleroma, [__MODULE__, :ex_aws_impl], ExAws)
@config_impl Application.compile_env(:pleroma, [__MODULE__, :config_impl], Pleroma.Config)

def put_file(%Pleroma.Upload{} = upload) do
  # Use @ex_aws_impl instead of ExAws directly
  case @ex_aws_impl.request(op) do
    {:ok, _} ->
      {:ok, {:file, s3_name}}

    error ->
      Logger.error("#{__MODULE__}: #{inspect(error)}")
      error
  end
end
```

### Step 3: Define the Mock in test/support/mocks.ex

Add your mock definition in the central mocks file:

```elixir
# In test/support/mocks.ex
Mox.defmock(Pleroma.Uploaders.S3.ExAwsMock, for: Pleroma.Uploaders.S3.ExAwsAPI)
```

### Step 4: Configure the Mock in Test Environment

In your test configuration (e.g., `config/test.exs`), specify which mock implementation to use:

```elixir
config :pleroma, Pleroma.Uploaders.S3, ex_aws_impl: Pleroma.Uploaders.S3.ExAwsMock
config :pleroma, Pleroma.Uploaders.S3, config_impl: Pleroma.UnstubbedConfigMock
```

## Writing Tests with Mox

### Setting Up Your Test

```elixir
defmodule Pleroma.Uploaders.S3Test do
  use Pleroma.DataCase, async: true  # Note: async: true is now possible!

  alias Pleroma.Uploaders.S3
  alias Pleroma.Uploaders.S3.ExAwsMock
  alias Pleroma.UnstubbedConfigMock, as: ConfigMock

  import Mox  # Import Mox functions
  
  # Note: verify_on_exit! is already called in DataCase setup
  # so you don't need to add it explicitly in your test module
end
```

### Setting Expectations with Mox

Mox uses an explicit expectation system. Here's how to use it:

```elixir
# Basic expectation for a function call
ExAwsMock
|> expect(:request, fn _req -> {:ok, %{status_code: 200}} end)

# Expectation for multiple calls with same response
ExAwsMock
|> expect(:request, 3, fn _req -> {:ok, %{status_code: 200}} end)

# Expectation with specific arguments
ExAwsMock
|> expect(:request, fn %{bucket: "test_bucket"} -> {:ok, %{status_code: 200}} end)

# Complex configuration mocking
ConfigMock
|> expect(:get, fn key ->
  [
    {Pleroma.Upload, [uploader: Pleroma.Uploaders.S3, base_url: "https://s3.amazonaws.com"]},
    {Pleroma.Uploaders.S3, [bucket: "test_bucket"]}
  ]
  |> get_in(key)
end)
```

### Understanding Mox Modes in Pleroma

Pleroma's DataCase automatically configures Mox differently based on whether your test is async or not:

1. **Async tests** (`async: true`):
   - Uses `Mox.set_mox_private()` - expectations are scoped to the current process
   - Stubs `Pleroma.CachexMock` with `Pleroma.NullCache`
   - Each test process has its own isolated mock expectations

2. **Non-async tests** (`async: false`):
   - Uses `Mox.set_mox_global()` - expectations are shared across processes
   - Stubs `Pleroma.CachexMock` with `Pleroma.CachexProxy`
   - Mock expectations can be set in one process and called from another

Choose the appropriate mode based on your test requirements. For most tests, async mode is preferred for better performance.

## Migrating from Mock/meck to Mox

Here's a step-by-step guide for migrating existing tests from Mock/meck to Mox:

### 1. Identify the Module to Mock

Look for `with_mock` or `test_with_mock` calls in your tests:

```elixir
# Old approach with Mock
with_mock ExAws, request: fn _ -> {:ok, :ok} end do
  assert S3.put_file(file_upload) == {:ok, {:file, "test_folder/image-tet.jpg"}}
end
```

### 2. Define a Behavior for the Module

Create a behavior that defines the functions you want to mock:

```elixir
defmodule Pleroma.Uploaders.S3.ExAwsAPI do
  @callback request(op :: ExAws.Operation.t()) :: {:ok, ExAws.Operation.t()} | {:error, term()}
end
```

### 3. Update Your Implementation to Use a Configurable Dependency

```elixir
# Old
def put_file(%Pleroma.Upload{} = upload) do
  case ExAws.request(op) do
    # ...
  end
end

# New
@ex_aws_impl Application.compile_env(:pleroma, [__MODULE__, :ex_aws_impl], ExAws)

def put_file(%Pleroma.Upload{} = upload) do
  case @ex_aws_impl.request(op) do
    # ...
  end
end
```

### 4. Define the Mock in mocks.ex

```elixir
Mox.defmock(Pleroma.Uploaders.S3.ExAwsMock, for: Pleroma.Uploaders.S3.ExAwsAPI)
```

### 5. Configure the Test Environment

```elixir
config :pleroma, Pleroma.Uploaders.S3, ex_aws_impl: Pleroma.Uploaders.S3.ExAwsMock
```

### 6. Update Your Tests to Use Mox

```elixir
# Old (with Mock)
test_with_mock "save file", ExAws, request: fn _ -> {:ok, :ok} end do
  assert S3.put_file(file_upload) == {:ok, {:file, "test_folder/image-tet.jpg"}}
  assert_called(ExAws.request(:_))
end

# New (with Mox)
test "save file" do
  ExAwsMock
  |> expect(:request, fn _req -> {:ok, %{status_code: 200}} end)

  assert S3.put_file(file_upload) == {:ok, {:file, "test_folder/image-tet.jpg"}}
end
```

### 7. Enable Async Testing

Now you can safely enable `async: true` in your test module:

```elixir
use Pleroma.DataCase, async: true
```

## Best Practices

1. **Always define behaviors**: They serve as contracts and documentation
2. **Keep mocks in a central location**: Use test/support/mocks.ex for all mock definitions
3. **Use verify_on_exit!**: This is already set up in DataCase, ensuring all expected calls were made
4. **Use specific expectations**: Be as specific as possible with your expectations
5. **Enable async: true**: Take advantage of Mox's concurrent testing capability
6. **Don't over-mock**: Only mock external dependencies that are difficult to test directly
7. **Leverage existing stubs**: Use the default stubs provided by DataCase when possible
8. **Avoid clear_config in async tests**: Use dependency injection and mocking instead

## Example: Complete Migration

For a complete example of migrating a test from Mock/meck to Mox, you can refer to commit `90a47ca050c5839e8b4dc3bac315dc436d49152d` in the Pleroma repository, which shows how the S3 uploader tests were migrated.

## Conclusion

Migrating tests from Mock/meck to Mox provides significant benefits for the Pleroma test suite, including faster test execution through async testing, better isolation between tests, and more robust mocking through explicit contracts. By following this guide, you can successfully migrate existing tests and write new tests using Mox. 