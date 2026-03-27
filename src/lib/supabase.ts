type QueryBuilder = {
  select: (..._args: unknown[]) => QueryBuilder
  eq: (..._args: unknown[]) => QueryBuilder
  gte: (..._args: unknown[]) => QueryBuilder
  lte: (..._args: unknown[]) => QueryBuilder
  in: (..._args: unknown[]) => QueryBuilder
  order: (..._args: unknown[]) => QueryBuilder
  limit: (..._args: unknown[]) => QueryBuilder
  single: (..._args: unknown[]) => Promise<{ data: any; error: any }>
  maybeSingle: (..._args: unknown[]) => Promise<{ data: any; error: any }>
  then: Promise<any>['then']
  catch: Promise<any>['catch']
}

const builder = (): QueryBuilder => {
  const p = Promise.resolve({ data: [], error: null })
  const q = {
    select: () => q,
    eq: () => q,
    gte: () => q,
    lte: () => q,
    in: () => q,
    order: () => q,
    limit: () => q,
    single: async () => ({ data: null, error: null }),
    maybeSingle: async () => ({ data: null, error: null }),
    then: p.then.bind(p),
    catch: p.catch.bind(p),
  }
  return q
}

export const supabase = {
  from: (_table: string) => builder(),
  rpc: async (_fn: string, _args?: Record<string, unknown>) => ({
    data: null,
    error: null,
  }),
}
