/// Riverpod's own default retry policy for a failed provider `build()`
/// (`ProviderContainer.defaultRetry`) silently retries up to 10 times with
/// exponential backoff capped at 6.4s between attempts - worst case, over a
/// minute of retries, all hidden behind the provider's `AsyncLoading` state,
/// before the UI ever sees a persistent `AsyncError` it can render.
///
/// That is exactly wrong for a screen backed by a network call: on a
/// genuinely offline/unreachable backend, the user is left staring at a
/// spinner for a very long time before the existing friendly error state
/// (with its own manual "tap to retry") ever appears. Passing this as a
/// provider's `retry:` disables the automatic retries so a single bounded
/// Dio/WebSocket timeout surfaces as a persistent error immediately -
/// retrying from there is the user's call via the existing retry UI, not a
/// silent background loop.
Duration? noAutoRetry(int retryCount, Object error) => null;
