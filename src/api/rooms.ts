import type { MrRoom } from '../types'

export async function fetchRooms(): Promise<MrRoom[]> {
  return []
}

export async function fetchApproversByRoomIds(
  _roomIds: string[]
): Promise<Record<string, string[]>> {
  return {}
}
