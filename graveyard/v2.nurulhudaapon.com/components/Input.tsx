export function SearchInput({
  setSearchValue,
  placeholder = 'Search',
  inputId = 'search'
}) {
  return (
    <div className="relative mb-4 w-full">
      <input
        id={inputId}
        aria-label={placeholder}
        type="text"
        onChange={(e) => setSearchValue(e.target.value)}
        placeholder={placeholder}
        className=" peer block w-full transform rounded-md border border-gray-200 bg-white px-4 py-2 text-gray-900 transition-all focus:scale-[1.1] focus:border-blue-500 focus:ring-blue-500 dark:border-gray-900 dark:text-gray-100 focus:dark:bg-gray-800"
      />
      <svg
        className="absolute right-3 top-3 h-5 w-full w-5 transform text-gray-400 transition-all peer-focus:translate-x-6 peer-focus:scale-[1.1] dark:text-gray-300"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={2}
          d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
        />
      </svg>
    </div>
  );
}
