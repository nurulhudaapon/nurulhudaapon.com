import type { NextApiRequest, NextApiResponse } from 'next';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {

  try {
    const count = await getGithubFollowers();

    return res.status(200).json({ followers: count });
  } catch (e) {
    return res.status(500).json({ message: e.message });
  }
}


const getGithubFollowers = async function () {
  const userResponse = await fetch('https://api.github.com/users/nurulhudaapon');
  // const userReposResponse = await fetch(
  //   'https://api.github.com/users/nurulhudaapon/repos?per_page=100'
  // );

  const user = await userResponse.json();
  // const repositories = await userReposResponse.json();

  // const mine = repositories.filter((repo) => !repo.fork);
  // const stars = mine.reduce((accumulator, repository) => {
  //   return accumulator + repository['stargazers_count'];
  // }, 0);

  return user.followers;

}
