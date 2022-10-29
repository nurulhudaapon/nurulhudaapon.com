import type { NextApiRequest, NextApiResponse } from 'next';
import { getTotalViewCount } from 'lib/database';

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  try {
    const totalViews = await getTotalViewCount();

    return res.status(200).json({ total: totalViews });
  } catch (e) {
    return res.status(500).json({ message: e.message });
  }
}
