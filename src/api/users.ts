import type { MrUser } from '../types'

export async function fetchMrUserByUid(_uid: string): Promise<MrUser | null> {
  return null
}

export function formatPhone(phone?: string | null): string {
  return phone ?? ''
}
