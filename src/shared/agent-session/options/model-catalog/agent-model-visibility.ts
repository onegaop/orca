export function isSelectableAgentModel(agent: string, id: string): boolean {
  if (agent !== 'kilo') {
    return true
  }
  // Kilo reports zero token prices for some paid routers too.
  return (
    id.startsWith('kilo/') &&
    (id.endsWith(':free') ||
      id === 'kilo/kilo-auto/free' ||
      id === 'kilo/openrouter/free' ||
      id === 'kilo/reflection/beam-free')
  )
}
