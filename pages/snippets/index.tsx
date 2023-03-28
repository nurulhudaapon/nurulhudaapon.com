import Container from 'components/Container';
import FunctionCard from 'components/FunctionCard';
import { InferGetStaticPropsType } from 'next';
import { apiService } from 'lib/api';
import { useState } from 'react';
import { SearchInput } from 'components/Input';

const PRIORITY_SORT = ['', 'low', 'medium', 'high'];

export default function Snippets({
  snippets
}: InferGetStaticPropsType<typeof getStaticProps>) {
  const sortedSnippets = snippets.sort((a, b) => {
    const aPriority = PRIORITY_SORT.indexOf(a.attributes.priority || '');
    const bPriority = PRIORITY_SORT.indexOf(b.attributes.priority || '');
    return bPriority - aPriority;
  });

  const [searchValue, setSearchValue] = useState('');
  const filteredSnippets = sortedSnippets.filter((snippet) =>
    JSON.stringify(snippet).toLowerCase().includes(searchValue.toLowerCase())
  );

  return (
    <Container
      title="Code Snippets – Nurul Huda (Apon)"
      description="Collection of various useful code snippets across different technologies."
    >
      <div className="flex flex-col items-start justify-center max-w-2xl mx-auto mb-16">
        <h1 className="mb-4 text-3xl font-bold tracking-tight text-black md:text-5xl dark:text-white">
          Code Snippets
        </h1>
        <p className="mb-4 text-gray-600 dark:text-gray-400">
          Collection of various useful code snippets across different
          technologies. If you have any suggestions, please feel free to
          contact.
        </p>

        <SearchInput
          setSearchValue={setSearchValue}
          placeholder="Search snippets"
        />
        <div className="grid w-full grid-cols-1 gap-4 my-2 mt-2 sm:grid-cols-2">
          {filteredSnippets.map((snippet) => (
            <FunctionCard
              key={snippet.attributes.slug}
              title={snippet.attributes.title}
              slug={snippet.attributes.slug}
              logo={snippet.attributes.logo}
              description={snippet.attributes.description}
            />
          ))}
        </div>
      </div>
    </Container>
  );
}

export async function getStaticProps({ preview = false }) {
  const snippets = await apiService.getSnippets();
  const filteredSnippets = snippets?.filter(
    (s) => s?.attributes?.visibility !== 'unlisted'
  );
  return { props: { snippets: filteredSnippets } };
}
