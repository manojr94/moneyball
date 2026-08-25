import PropTypes from 'prop-types'

export function ErrorMessage({ message }) {
  return (
    <div className="error-message" role="alert">
      <strong>Error:</strong> {message}
    </div>
  )
}

ErrorMessage.propTypes = { message: PropTypes.string.isRequired }
