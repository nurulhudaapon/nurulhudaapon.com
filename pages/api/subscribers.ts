import { apiService } from 'lib/api';
import { createSubscriber, createVisitor, getSubscriberByEmail } from 'lib/database';
import type { NextApiRequest, NextApiResponse } from 'next';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
    if (req.method == 'POST') {
        const { email, ip } = JSON.parse(req.body);


        // get visitor id from cookie
        let visitorId = req.cookies['visitor_id']

        // create visitor if not exists
        if (!visitorId)
        {
        const createdVisitor = await createVisitor(
            req.headers['x-forwarded-for'] as string,
            ip,
        )

        res.setHeader('Set-Cookie', `visitor_id=${createdVisitor.insertedId}; Path=/; SameSite=Strict`);
        visitorId = createdVisitor.insertedId.toString();
        }

        // const currentSubscriber = await apiService.getUserByEmail(email);
        const currentSubscriber = await getSubscriberByEmail(email);

        if (currentSubscriber?._id) return res.status(200).json(currentSubscriber);

        // const subscriber = await apiService.registerSubscriber({ email });
        const subscriber = await createSubscriber(email, visitorId, ip);

        return res.status(201).json(subscriber);
    }

    try {
        // const count = await apiService.getUserCount();

        res.setHeader('Cache-Control', 'public, s-maxage=1200, stale-while-revalidate=600');

        return res.status(200).json({ count: 0 });
    } catch (e) {
        return res.status(500).json({ message: e.message });
    }
}
