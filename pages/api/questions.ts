import { apiService } from 'lib/api';
import { createQuestion, createVisitor, getQuestions } from 'lib/database';
import type { NextApiRequest, NextApiResponse } from 'next';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
    if (req.method == 'POST') {
        const { email, question, visitor } = JSON.parse(req.body);

        // get visitor id from cookie
        let visitorId = req.cookies['visitor_id']

        // create visitor if not exists
        if (!visitorId)
        {
        const createdVisitor = await createVisitor(
            req.headers['x-forwarded-for'] as string,
            visitor,
        )

        res.setHeader('Set-Cookie', `visitor_id=${createdVisitor.insertedId}; Path=/; SameSite=Strict`);
        visitorId = createdVisitor.insertedId.toString();
        }

        const createdQuestion = await createQuestion(question, email, visitorId, visitor);

        // const currentSubscriber = await apiService.getUserByEmail(email);

        // if (currentSubscriber?.length) return res.status(200).json(currentSubscriber);

        // const subscriber = await apiService.registerSubscriber({ email });

        return res.status(201).json(createdQuestion);
    }

    try {
        // const count = await apiService.getUserCount();

        // res.setHeader('Cache-Control', 'public, s-maxage=1200, stale-while-revalidate=600');

        // return res.status(200).json({ count });
        let visitorId = req.cookies['visitor_id']

        if (!visitorId)
        {
            // return not found
            return res.status(404).json({ message: 'Not found' });
        }

        const questions = await getQuestions(visitorId);

        return res.status(200).json(questions);
    } catch (e) {
        return res.status(500).json({ message: e.message });
    }
}
