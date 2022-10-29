import type { NextApiRequest, NextApiResponse } from 'next';
import { createView, getViewCount } from 'lib/database';

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  try {
    const slug = req.query.slug.toString();

    if (req.method === 'POST') {
      const newOrUpdatedViews = await createView(req.headers['x-forwarded-for'] as string, slug, 'post');
      const views = await getViewCount(slug, 'post');

      return res.status(200).json({
        total: views
      });
    }

    if (req.method === 'GET') {
      const views = await getViewCount(slug, 'post');

      return res.status(200).json({ total: views });
    }
  } catch (e) {
    return res.status(500).json({ message: e.message });
  }
}
