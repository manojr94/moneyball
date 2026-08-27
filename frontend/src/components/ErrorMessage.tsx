export function ErrorMessage({ message }: { message: string }) {
  return (
    <div
      className="rounded-md bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-800"
      role="alert"
    >
      <strong className="font-medium">Error:</strong> {message}
    </div>
  )
}
