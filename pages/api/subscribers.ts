import { createSubscriber, getTotalSubscriberCount } from 'lib/database';
import type { NextApiRequest, NextApiResponse } from 'next';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method == 'POST')
  {
    const { email } = JSON.parse(req.body);
    const subscriber = await createSubscriber(email);
    return res.status(201).json(subscriber);
  } 

  try {
    const count = await getTotalSubscriberCount();

    return res.status(200).json({ count });
  } catch (e) {
    return res.status(500).json({ message: e.message });
  }
}
