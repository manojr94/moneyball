import PropTypes from 'prop-types'

export function ErrorMessage({ message }) {
  return (
    <div
      className="rounded-md bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-800"
      role="alert"
    >
      <strong className="font-medium">Error:</strong> {message}
    </div>
  )
}

ErrorMessage.propTypes = { message: PropTypes.string.isRequired }
