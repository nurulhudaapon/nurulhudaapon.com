import { apiService } from 'lib/api';
import type { NextApiRequest, NextApiResponse } from 'next';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
    if (req.method == 'POST') {
        const { email } = JSON.parse(req.body);
        const currentSubscriber = await apiService.getUserByEmail(email);

        if (currentSubscriber) return res.status(200).json(currentSubscriber);

        const subscriber = await apiService.registerSubscriber({ email });

        return res.status(201).json(subscriber);
    }

    try {
        const count = await apiService.getUserCount();

        return res.status(200).json({ count });
    } catch (e) {
        return res.status(500).json({ message: e.message });
    }
}
